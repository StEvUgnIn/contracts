pragma solidity ^0.6.0;

import "@c-layer/common/contracts/core/Proxy.sol";
import "@c-layer/common/contracts/operable/Ownable.sol";
import "@c-layer/common/contracts/operable/OperableAsCore.sol";
import "../interface/IVotingSessionManager.sol";
import "./VotingSessionStorage.sol";


/**
 * @title VotingSessionManager
 * @dev VotingSessionManager contract
 * @author Cyril Lapinte - <cyril.lapinte@openfiz.com>
 * SPDX-License-Identifier: MIT
 *
 * Error messages
 *   VSM01: Session doesn't exist
 *   VSM02: Proposal doesn't exist
 *   VSM03: Token has no valid core
 *   VSM04: Proposal was cancelled
 *   VSM05: Campaign period must be within valid range
 *   VSM06: Voting period must be within valid range
 *   VSM07: Execution period must be within valid range
 *   VSM08: Grace period must be within valid range
 *   VSM09: Period offset must be within valid range
 *   VSM10: Open proposals limit must be lower than the max proposals limit
 *   VSM11: Operator proposal limit must be greater than 0
 *   VSM12: New proposal threshold must be greater than 0
 *   VSM13: The current session is not in GRACE, CLOSED or ARCHIVED state
 *   VSM14: Duplicates entries are not allowed in non voting contracts
 *   VSM15: Inconsistent numbers of methods signatures
 *   VSM16: Inconsistent numbers of min participations
 *   VSM17: Inconsistent numbers of quorums
 *   VSM18: Inconsistent numbers of execution thresholds
 *   VSM19: Default majority cannot be null
 *   VSM20: Execute resolution threshold must be greater than 0
 *   VSM21: Only contract owner may define its sponsor
 *   VSM22: Operator proposal limit is reached
 *   VSM23: Too many proposals yet for this session
 *   VSM24: Not enough tokens for a new proposal
 *   VSM25: Current session is not in PLANNED state
 *   VSM26: Only the author can update a proposal
 *   VSM27: Proposal must not be already cancelled
 *   VSM28: The previous session can only be in GRACE state to allow rules change
 *   VSM29: Not enough tokens to execute
 *   VSM30: Voting Session resolutions are not allowed in EXECUTION
 *   VSM31: Only Voting Session operations are allowed in GRACE
 *   VSM32: The proposal is not in APPROVED state
 *   VSM33: Invalid resolution order
 *   VSM34: The resolution must be successfull
 *   VSM35: The session is too recent to be archived
 *   VSM36: Unable to set the lock
 *   VSM37: Cannot depends on itself or inexisting porposal
 *   VSM38: Reference proposal for alternates must have the lowest proposalId
 *   VSM39: Session is not in VOTING state
 *   VSM40: Voters must be provided
 *   VSM41: Sender must be either the voter, the voter's sponsor or an operator
 *   VSM42: The voter must not have already voted for this session
 *   VSM43: Cannot submit multiple votes for a proposal and its alternatives
 *   VSM44: The vote contains too many proposals
 */
contract VotingSessionManager is VotingSessionStorage, IVotingSessionManager, OperableAsCore, Proxy {

  modifier onlyExistingSession(uint256 _sessionId) {
    require(_sessionId >= oldestSessionId_ && _sessionId <= currentSessionId_, "VSM01");
    _;
  }

  modifier onlyExistingProposal(uint256 _sessionId, uint8 _proposalId) {
    require(_sessionId >= oldestSessionId_ && _sessionId <= currentSessionId_, "VSM01");
    require(_proposalId > 0 && _proposalId <= sessions[_sessionId].proposalsCount, "VSM02");
    _;
  }

  /**
   * @dev constructor
   */
  constructor(ITokenProxy _token) public Proxy(_token.core()) {
    token_ = _token;
    require(address(core) != address(0), "VSM03");

    resolutionRequirements[ANY_TARGET][ANY_METHOD] =
      ResolutionRequirement(DEFAULT_MAJORITY, DEFAULT_QUORUM, DEFAULT_EXECUTION_THRESHOLD);
  }

  /**
   * @dev token
   */
  function token() public override view returns (ITokenProxy) {
    return token_;
  }

  /**
   * @dev sessionRule
   */
  function sessionRule() public override view returns (
    uint64 campaignPeriod,
    uint64 votingPeriod,
    uint64 executionPeriod,
    uint64 gracePeriod,
    uint64 periodOffset,
    uint8 openProposals,
    uint8 maxProposals,
    uint8 maxProposalsOperator,
    uint256 newProposalThreshold,
    address[] memory nonVotingAddresses) {
    return (
      sessionRule_.campaignPeriod,
      sessionRule_.votingPeriod,
      sessionRule_.executionPeriod,
      sessionRule_.gracePeriod,
      sessionRule_.periodOffset,
      sessionRule_.openProposals,
      sessionRule_.maxProposals,
      sessionRule_.maxProposalsOperator,
      sessionRule_.newProposalThreshold,
      sessionRule_.nonVotingAddresses);
  }

  /**
   * @dev resolutionRequirement
   */
  function resolutionRequirement(address _target, bytes4 _method) public override view returns (
    uint128 majority,
    uint128 quorum,
    uint256 executionThreshold) {
    ResolutionRequirement storage requirement =
      resolutionRequirements[_target][_method];

    return (
      requirement.majority,
      requirement.quorum,
      requirement.executionThreshold);
  }

  /**
   * @dev oldestSessionId
   */
  function oldestSessionId() public override view returns (uint256) {
    return oldestSessionId_;
  }

  /**
   * @dev currentSessionId
   */
  function currentSessionId() public override view returns (uint256) {
    return currentSessionId_;
  }

  /**
   * @dev session
   */
  function session(uint256 _sessionId) public override
    onlyExistingSession(_sessionId) view returns (
    uint64 campaignAt,
    uint64 voteAt,
    uint64 executionAt,
    uint64 graceAt,
    uint64 closedAt,
    uint256 proposalsCount,
    uint256 participation,
    uint256 totalSupply,
    uint256 votingSupply)
  {
    Session storage session_ = sessions[_sessionId];
    return (
      session_.campaignAt,
      session_.voteAt,
      session_.executionAt,
      session_.graceAt,
      session_.closedAt,
      session_.proposalsCount,
      session_.participation,
      session_.totalSupply,
      session_.votingSupply);
  }

  /**
   * @dev sponsorOf
   */
  function sponsorOf(address _voter) public override view returns (address address_, uint64 until) {
    Sponsor storage sponsor_ = sponsors[_voter];
    address_ = sponsor_.address_;
    until = sponsor_.until;
  }

  /**
   * @dev lastVoteOf
   */
  function lastVoteOf(address _voter) public override view returns (uint64 at) {
    return lastVotes[_voter];
  }

  /**
   * @dev proposal
   */
  function proposal(uint256 _sessionId, uint8 _proposalId) public override
    onlyExistingProposal(_sessionId, _proposalId) view returns (
    string memory name,
    string memory url,
    bytes32 proposalHash,
    address resolutionTarget,
    bytes memory resolutionAction)
  {
    Proposal storage proposal_ = sessions[_sessionId].proposals[_proposalId];
    return (
      proposal_.name,
      proposal_.url,
      proposal_.proposalHash,
      proposal_.resolutionTarget,
      proposal_.resolutionAction);
  }

  /**
   * @dev proposalData
   */
  function proposalData(uint256 _sessionId, uint8 _proposalId) public override
    onlyExistingProposal(_sessionId, _proposalId) view returns (
    address proposedBy,
    uint128 requirementMajority,
    uint128 requirementQuorum,
    uint8 dependsOn,
    uint8 alternativeOf,
    uint256 alternativesMask,
    uint256 approvals)
  {
    Proposal storage proposal_ = sessions[_sessionId].proposals[_proposalId];
    return (
      proposal_.proposedBy,
      proposal_.requirement.majority,
      proposal_.requirement.quorum,
      proposal_.dependsOn,
      proposal_.alternativeOf,
      proposal_.alternativesMask,
      proposal_.approvals);
  }

  /**
   * @dev nextSessionAt
   */
  function nextSessionAt(uint256 _time) public override view returns (uint256 at) {
    uint256 sessionPeriod =
      sessionRule_.campaignPeriod
      + sessionRule_.votingPeriod
      + sessionRule_.executionPeriod
      + sessionRule_.gracePeriod;

    uint256 currentSessionClosedAt;
    if (currentSessionId_ > 0) {
      currentSessionClosedAt = uint256(sessions[currentSessionId_].closedAt);
    }

    at = (_time > currentSessionClosedAt) ? _time : currentSessionClosedAt;
    at =
      ((at + sessionRule_.campaignPeriod) / sessionPeriod + 1) * sessionPeriod + sessionRule_.periodOffset;
  }

  /**
   * @dev sessionStateAt
   */
  function sessionStateAt(uint256 _sessionId, uint256 _time) public override
    view returns (SessionState)
  {
    if (_sessionId == 0 || _sessionId > currentSessionId_) {
      return SessionState.UNDEFINED;
    }

    if (_sessionId < oldestSessionId_) {
      return SessionState.ARCHIVED;
    }

    Session storage session_ = sessions[_sessionId];

    if (_time < uint256(session_.campaignAt)) {
      return SessionState.PLANNED;
    }

    if (_time < uint256(session_.voteAt)) {
      return SessionState.CAMPAIGN;
    }

    if (_time < uint256(session_.executionAt))
    {
      return SessionState.VOTING;
    }

    if (_time < uint256(session_.graceAt))
    {
      return SessionState.EXECUTION;
    }

    if (_time < uint256(session_.closedAt))
    {
      return SessionState.GRACE;
    }

    return SessionState.CLOSED;
  }

  /**
   * @dev newProposalThresholdAt
   */
  function newProposalThresholdAt(uint256 _sessionId, uint256 _proposalsCount) public override
    onlyExistingSession(_sessionId) view returns (uint256)
  {
    Session storage session_ = sessions[_sessionId];
    bool baseThreshold = (
      sessionRule_.maxProposals <= sessionRule_.openProposals
      || _proposalsCount <= sessionRule_.openProposals
      || session_.totalSupply <= sessionRule_.newProposalThreshold);

    return (baseThreshold) ? sessionRule_.newProposalThreshold : sessionRule_.newProposalThreshold.add(
      (session_.totalSupply.div(2)).sub(sessionRule_.newProposalThreshold).mul(
        (_proposalsCount - sessionRule_.openProposals) ** 2).div((sessionRule_.maxProposals - sessionRule_.openProposals) ** 2));
  }

  /**
   * @dev proposalApproval
   */
  function proposalApproval(uint256 _sessionId, uint8 _proposalId) public override
    onlyExistingProposal(_sessionId, _proposalId) view returns (bool)
  {
    Session storage session_ = sessions[_sessionId];
    Proposal storage proposal_ = session_.proposals[_proposalId];
    return session_.participation != 0
      && proposal_.approvals.mul(PERCENT).div(session_.participation) >= proposal_.requirement.majority
      && session_.participation.mul(PERCENT).div(session_.totalSupply) >= proposal_.requirement.quorum;
  }

  /**
   * @dev proposalStateAt
   */
  function proposalStateAt(uint256 _sessionId, uint8 _proposalId, uint256 _time)
    public override view returns (ProposalState)
  {
    Session storage session_ = sessions[_sessionId];
    SessionState sessionState = sessionStateAt(_sessionId, _time);

    if (sessionState == SessionState.ARCHIVED) {
      return ProposalState.ARCHIVED;
    }

    if (sessionState == SessionState.UNDEFINED
      || _proposalId == 0 || _proposalId > session_.proposalsCount) {
      return ProposalState.UNDEFINED;
    }

    Proposal storage proposal_ = session_.proposals[_proposalId];

    if (proposal_.cancelled) {
      return ProposalState.CANCELLED;
    }

    if (sessionState < SessionState.CAMPAIGN) {
      return ProposalState.DEFINED;
    }

    if (sessionState < SessionState.EXECUTION) {
      return ProposalState.LOCKED;
    }

    if (proposal_.resolutionExecuted) {
      return ProposalState.RESOLVED;
    }

    if (sessionState == SessionState.CLOSED) {
      return ProposalState.CLOSED;
    }
    
    return proposalApproval(_sessionId, _proposalId) ? ProposalState.APPROVED : ProposalState.REJECTED;
  }

  /**
   * @dev updateSessionRule
   */
  function updateSessionRule(
    uint64 _campaignPeriod,
    uint64 _votingPeriod,
    uint64 _executionPeriod,
    uint64 _gracePeriod,
    uint64 _periodOffset,
    uint8 _openProposals,
    uint8 _maxProposals,
    uint8 _maxProposalsOperator,
    uint256 _newProposalThreshold,
    address[] memory _nonVotingAddresses
  )  public override onlyProxyOperator(Proxy(this)) returns (bool) {
    require(_campaignPeriod >= MIN_PERIOD_LENGTH && _campaignPeriod <= MAX_PERIOD_LENGTH, "VSM05");
    require(_votingPeriod >= MIN_PERIOD_LENGTH && _votingPeriod <= MAX_PERIOD_LENGTH, "VSM06");
    require(_executionPeriod >= MIN_PERIOD_LENGTH && _executionPeriod <= MAX_PERIOD_LENGTH, "VSM07");
    require(_gracePeriod > _campaignPeriod && _gracePeriod <= MAX_PERIOD_LENGTH, "VSM08");
    require(_periodOffset <= MAX_PERIOD_LENGTH, "VSM09");

    require(_openProposals <= _maxProposals, "VSM10");
    require(_maxProposalsOperator !=0, "VSM11");
    require(_newProposalThreshold != 0, "VSM12");

    if (currentSessionId_ != 0) {
      SessionState state = sessionStateAt(currentSessionId_, currentTime());
      require(state == SessionState.GRACE ||
        state == SessionState.CLOSED || state == SessionState.ARCHIVED, "VSM13");
    }

    uint256 currentTime_ = currentTime();
    for (uint256 i=0; i < sessionRule_.nonVotingAddresses.length; i++) {
      lastVotes[sessionRule_.nonVotingAddresses[i]] = uint64(currentTime_);
    }

    for (uint256 i=0; i < _nonVotingAddresses.length; i++) {
      lastVotes[_nonVotingAddresses[i]] = ~uint64(0);

      for (uint256 j=i+1; j < _nonVotingAddresses.length; j++) {
        require(_nonVotingAddresses[i] != _nonVotingAddresses[j], "VSM14");
      }
    }

    sessionRule_ = SessionRule(
      _campaignPeriod,
      _votingPeriod,
      _executionPeriod,
      _gracePeriod,
      _periodOffset,
      _openProposals,
      _maxProposals,
      _maxProposalsOperator,
      _newProposalThreshold,
      _nonVotingAddresses);

    emit SessionRuleUpdated(
      _campaignPeriod,
      _votingPeriod,
      _executionPeriod,
      _gracePeriod,
      _periodOffset,
      _openProposals,
      _maxProposals,
      _maxProposalsOperator,
      _newProposalThreshold,
      _nonVotingAddresses);
    return true;
  }

  /**
   * @dev updateResolutionRequirements
   */
  function updateResolutionRequirements(
    address[] memory _targets,
    bytes4[] memory _methodSignatures,
    uint128[] memory _majorities,
    uint128[] memory _quorums,
    uint256[] memory _executionThresholds
  ) public override onlyProxyOperator(Proxy(this)) returns (bool)
  {
    require(_targets.length == _methodSignatures.length, "VSM15");
    require(_methodSignatures.length == _majorities.length, "VSM16");
    require(_methodSignatures.length == _quorums.length, "VSM17");
    require(_methodSignatures.length == _executionThresholds.length, "VSM18");

    if (currentSessionId_ != 0) {
      SessionState state = sessionStateAt(currentSessionId_, currentTime());
      require(state == SessionState.GRACE ||
        state == SessionState.CLOSED || state == SessionState.ARCHIVED, "VSM13");
    }

    for (uint256 i=0; i < _methodSignatures.length; i++) {
      // Majority can only be 0 if it is not the global default, allowing the deletion of the requirement
      require(_majorities[i] != 0 || !(_targets[i] == ANY_TARGET && _methodSignatures[i] == ANY_METHOD), "VSM19");
      require(_executionThresholds[i] != 0 || _majorities[i] == 0, "VSM20");

      resolutionRequirements[_targets[i]][_methodSignatures[i]] =
        ResolutionRequirement(_majorities[i], _quorums[i], _executionThresholds[i]);
      emit ResolutionRequirementUpdated(
         _targets[i], _methodSignatures[i], _majorities[i], _quorums[i], _executionThresholds[i]);
    }
    return true;
  }

  /**
   * @dev defineSponsor
   */
  function defineSponsor(address _sponsor, uint64 _until) public override returns (bool) {
    sponsors[msg.sender] = Sponsor(_sponsor, _until);
    emit SponsorDefined(msg.sender, _sponsor, _until);
    return true;
  }

  /**
   * @dev defineContractSponsor
   */
  function defineContractSponsor(address _contract, address _sponsor, uint64 _until)
    public override returns (bool)
  {
    require(Ownable(_contract).owner() == msg.sender, "VSM21");
    sponsors[_contract] = Sponsor(_sponsor, _until);
    emit SponsorDefined(_contract, _sponsor, _until);
    return true;
  }

  /**
   * @dev defineProposal
   */
  function defineProposal(
    string memory _name,
    string memory _url,
    bytes32 _proposalHash,
    address _resolutionTarget,
    bytes memory _resolutionAction,
    uint8 _dependsOn,
    uint8 _alternativeOf) public override returns (bool)
  {
    Session storage session_ = loadSessionInternal();
    uint256 balance = token_.balanceOf(msg.sender);

    if (isProxyOperator(msg.sender, token_)) {
      require(session_.proposalsCount < sessionRule_.maxProposalsOperator, "VSM22");
    } else {
      require(session_.proposalsCount < sessionRule_.maxProposals, "VSM23");
      require(balance >= newProposalThresholdAt(currentSessionId_, session_.proposalsCount), "VSM24");
    }

    uint8 proposalId = ++session_.proposalsCount;
    updateProposalInternal(proposalId,
      _name, _url, _proposalHash, _resolutionTarget, _resolutionAction, _dependsOn, _alternativeOf);
    session_.proposals[proposalId].proposedBy = msg.sender;
 
    emit ProposalDefined(currentSessionId_, proposalId);
    return true;
  }

  /**
   * @dev updateProposal
   */
  function updateProposal(
    uint8 _proposalId,
    string memory _name,
    string memory _url,
    bytes32 _proposalHash,
    address _resolutionTarget,
    bytes memory _resolutionAction,
    uint8 _dependsOn,
    uint8 _alternativeOf
  ) public override onlyExistingProposal(currentSessionId_, _proposalId) returns (bool)
  {
    uint256 sessionId = currentSessionId_;
    require(sessionStateAt(sessionId, currentTime()) == SessionState.PLANNED, "VSM25");
    require(msg.sender == sessions[sessionId].proposals[_proposalId].proposedBy, "VSM26");

    updateProposalInternal(_proposalId,
      _name, _url, _proposalHash, _resolutionTarget, _resolutionAction, _dependsOn, _alternativeOf);

    emit ProposalUpdated(sessionId, _proposalId);
    return true;
  }

  /**
   * @dev cancelProposal
   */
  function cancelProposal(uint8 _proposalId)
    public override onlyExistingProposal(currentSessionId_, _proposalId) returns (bool)
  {
    uint256 sessionId = currentSessionId_;
    require(sessionStateAt(sessionId, currentTime()) == SessionState.PLANNED, "VSM25");
    Proposal storage proposal_ = sessions[sessionId].proposals[_proposalId];
    
    require(msg.sender == proposal_.proposedBy, "VSM26");
    require(!proposal_.cancelled, "VSM27");

    proposal_.cancelled = true;
    emit ProposalCancelled(sessionId, _proposalId);
    return true;
  }

  /**
   * @dev submitVote
   */
  function submitVote(uint256 _votes) public override returns (bool)
  {
    address[] memory voters = new address[](1);
    voters[0] = msg.sender;
    submitVoteInternal(voters, _votes);
    return true;
  }

  /**
   * @dev submitVoteOnBehalf
   */
  function submitVoteOnBehalf(
    address[] memory _voters,
    uint256 _votes
  ) public override returns (bool)
  {
    submitVoteInternal(_voters, _votes);
    return true;
  }

  /**
   * @dev execute resolutions
   */
  function executeResolutions(uint8[] memory _proposalIds) public override returns (bool)
  {
    uint256 balance = ~uint256(0);
    if (!isProxyOperator(msg.sender, token_)) {
      balance = token_.balanceOf(msg.sender);
    }

    uint256 currentTime_ = currentTime();
    uint256 sessionId = currentSessionId_;
    SessionState sessionState = sessionStateAt(sessionId, currentTime_);

    if (sessionState != SessionState.EXECUTION && sessionState != SessionState.GRACE) {
      sessionState = sessionStateAt(--sessionId, currentTime_);
      require(sessionState == SessionState.GRACE, "VSM28");
    }

    Session storage session_ = sessions[sessionId];
    for (uint256 i=0; i < _proposalIds.length; i++) {
      uint8 proposalId = _proposalIds[i];
      Proposal storage proposal_ = session_.proposals[proposalId];

      require(balance >= proposal_.requirement.executionThreshold, "VSM29");
      if (sessionState == SessionState.EXECUTION) {
        require(proposal_.resolutionTarget != address(this), "VSM30");
      } else {
        require(proposal_.resolutionTarget == address(this), "VSM31");
      }

      require(proposalStateAt(sessionId, proposalId, currentTime_) == ProposalState.APPROVED, "VSM32");
      if (proposal_.dependsOn != 0) {
        ProposalState dependsOnState = proposalStateAt(sessionId, proposal_.dependsOn, currentTime_);
        require(dependsOnState != ProposalState.APPROVED, "VSM33");
      }

      proposal_.resolutionExecuted = true;
      if (proposal_.resolutionTarget != ANY_TARGET) {
        // solhint-disable-next-line avoid-call-value, avoid-low-level-calls
        (bool success, ) = proposal_.resolutionTarget.call(proposal_.resolutionAction);
        require(success, "VSM34");
      }

      emit ResolutionExecuted(sessionId, proposalId);
    }
    return true;
  }

  /**
   * @dev archiveSession
   **/
  function archiveSession() public override onlyExistingSession(oldestSessionId_) returns (bool) {
    Session storage session_ = sessions[oldestSessionId_];
    require((currentSessionId_ >= (oldestSessionId_ + SESSION_RETENTION_COUNT)) ||
      (currentTime() > (SESSION_RETENTION_PERIOD + session_.voteAt)), "VSM35");
    for (uint256 i=0; i < session_.proposalsCount; i++) {
      delete session_.proposals[i];
    }
    delete sessions[oldestSessionId_];
    emit SessionArchived(oldestSessionId_++);
  }

  /**
   * @dev read signature
   * @param _data contains the selector
   */
  function readSignatureInternal(bytes memory _data) internal pure returns (bytes4 signature) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      signature := mload(add(_data, 0x20))
    }
  }

  /**
   * @dev load session internal
   */
  function loadSessionInternal() internal returns (Session storage session_) {
    uint256 currentTime_ = currentTime();

    SessionState state = SessionState.CLOSED;
    if (currentSessionId_ != 0) {
      state = sessionStateAt(currentSessionId_, currentTime_);
    }

    if (state != SessionState.PLANNED) {
      // Creation of a new session
      require(state == SessionState.GRACE ||
        state == SessionState.CLOSED || state == SessionState.ARCHIVED, "VSM13");
      uint256 nextStartAt = nextSessionAt(currentTime_);
      session_ = sessions[++currentSessionId_];
      session_.campaignAt = uint64(nextStartAt.sub(sessionRule_.campaignPeriod));
      session_.voteAt = uint64(nextStartAt);

      uint256 at = nextStartAt.add(sessionRule_.votingPeriod);
      session_.executionAt = uint64(at);
      at = at.add(sessionRule_.executionPeriod);
      session_.graceAt = uint64(at);
      at = at.add(sessionRule_.gracePeriod);
      session_.closedAt = uint64(at);
      session_.totalSupply = token_.totalSupply();

      require(ITokenCore(core).defineLock(
        address(this),
        ANY_ADDRESSES,
        ANY_ADDRESSES,
        session_.voteAt,
        session_.executionAt), "VSM36");

      emit SessionScheduled(currentSessionId_, session_.voteAt);

      if (currentSessionId_ >= (oldestSessionId_ + SESSION_RETENTION_COUNT)) {
        // Archiving of the oldest session
        archiveSession();
      }
    } else {
      session_ = sessions[currentSessionId_];
    }
  }

  /**
   * @dev updateProposalInternal
   */
  function updateProposalInternal(
    uint8 _proposalId,
    string memory _name,
    string memory _url,
    bytes32 _proposalHash,
    address _resolutionTarget,
    bytes memory _resolutionAction,
    uint8 _dependsOn,
    uint8 _alternativeOf) internal
  {
    Session storage session_ = sessions[currentSessionId_];

    require(_dependsOn <= session_.proposalsCount && _dependsOn != _proposalId, "VSM37");
    require(_alternativeOf < _proposalId, "VSM38");

    Proposal storage proposal_ = session_.proposals[_proposalId];
    proposal_.name = _name;
    proposal_.url = _url;
    proposal_.proposalHash = _proposalHash;
    proposal_.resolutionTarget = _resolutionTarget;
    proposal_.resolutionAction = _resolutionAction;
    proposal_.dependsOn = _dependsOn;

    if (proposal_.alternativeOf != _alternativeOf) {
      uint256 proposalBit = 1 << uint256(_proposalId-1);

      Proposal storage baseProposal;
      if (proposal_.alternativeOf != 0) {
        baseProposal = session_.proposals[proposal_.alternativeOf];
        baseProposal.alternativesMask ^= proposalBit;
      }
      if (_alternativeOf != 0) {
        baseProposal = session_.proposals[_alternativeOf];
        baseProposal.alternativesMask |= (1 << uint256(_alternativeOf-1)) | proposalBit;
      }
      proposal_.alternativeOf = _alternativeOf;
    }

    bytes4 actionSignature = readSignatureInternal(proposal_.resolutionAction);
    ResolutionRequirement storage requirement =
      resolutionRequirements[proposal_.resolutionTarget][actionSignature];

    if (requirement.majority == 0) {
      requirement = resolutionRequirements[proposal_.resolutionTarget][bytes4(ANY_METHOD)];
    }

    if (requirement.majority == 0) {
      requirement = resolutionRequirements[ANY_TARGET][actionSignature];
    }

    if (requirement.majority == 0) {
      requirement = resolutionRequirements[ANY_TARGET][bytes4(ANY_METHOD)];
    }
    proposal_.requirement =
      ResolutionRequirement(
        requirement.majority,
        requirement.quorum,
        requirement.executionThreshold);
  }

  function updateVotingSupply() internal {
    Session storage session_ = sessions[currentSessionId_];
    session_.votingSupply = session_.totalSupply;
    for (uint256 i=0; i < sessionRule_.nonVotingAddresses.length; i++) {
      session_.votingSupply =
        session_.votingSupply.sub(token_.balanceOf(sessionRule_.nonVotingAddresses[i]));
    }
  }


  /**
   * @dev submit vote for proposals internal
   */
  function submitVoteInternal(
    address[] memory _voters,
    uint256 _votes) internal
  {
    require(sessionStateAt(currentSessionId_, currentTime()) == SessionState.VOTING, "VSM39");
    Session storage session_ = sessions[currentSessionId_];
    require(_voters.length > 0, "VSM40");

    if(session_.participation == 0) {
      // The token is now locked and supply should not change anymore
      updateVotingSupply();
    }

    uint256 weight = 0;
    uint64 currentTime_ = uint64(currentTime());
    bool isOperator = isProxyOperator(msg.sender, token_);

    for (uint256 i=0; i < _voters.length; i++) {
      address voter = _voters[i];

      require(voter == msg.sender ||
        (isOperator && !ITokenCore(core).isSelfManaged(voter)) ||
        (sponsors[voter].address_ == msg.sender && sponsors[voter].until  >= currentTime_), "VSM41");
      require(lastVotes[voter] < session_.voteAt, "VSM42");
      uint256 balance = token_.balanceOf(voter);
      weight += balance;
      lastVotes[voter] = currentTime_;
      emit Vote(currentSessionId_, voter, balance);
    }

    uint256 remainingVotes = _votes;
    for (uint256 i=1; i <= session_.proposalsCount && remainingVotes != 0; i++) {
      Proposal storage proposal_ = session_.proposals[i];

      if (!proposal_.cancelled && (remainingVotes & 1) == 1) {
        if (proposal_.alternativeOf != 0) {
          Proposal storage baseProposal = session_.proposals[proposal_.alternativeOf];
          require (baseProposal.alternativesMask & _votes == (1 << (i-1)), "VSM43");
        }

        proposal_.approvals += weight;
      }
      remainingVotes = remainingVotes >> 1;
    }
    require(remainingVotes == 0, "VSM44");
    session_.participation += weight;
  }
}
