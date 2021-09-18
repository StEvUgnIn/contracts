pragma solidity ^0.8.0;

import "@c-layer/common/contracts/signer/SignerRecovery.sol";


/**
 * @title MultiSig
 * @dev MultiSig contract
 * @author Cyril Lapinte - <cyril@openfiz.com>
 * SPDX-License-Identifier: MIT
 *
 * Error messages
 * MS01: Valid signatures below threshold
 * MS02: Transaction validity has expired
 * MS03: Sender does not belong to signers
 * MS04: Execution should be correct
 */
contract MultiSig {
  using SignerRecovery for bytes;

  address[] internal signers_;
  uint8 internal threshold_;

  bytes32 internal replayProtection_;
  uint256 internal nonce_;

  /**
   * @dev constructor
   */
  constructor(address[] memory _signers, uint8 _threshold) {
    signers_ = _signers;
    threshold_ = _threshold;

    // Prevent first transaction of different contracts
    // to be replayed here
    updateReplayProtection();
  }

  /**
   * @dev receive function
   */
  // solhint-disable-next-line no-empty-blocks
  receive() virtual external payable {}

  /**
   * @dev fallback function
   */
  // solhint-disable-next-line no-empty-blocks
  fallback() virtual external payable {}

  /**
   * @dev read a function selector from a bytes field
   * @param _data contains the selector
   */
  function readSelector(bytes memory _data) public pure returns (bytes4) {
    bytes4 selector;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      selector := mload(add(_data, 0x20))
    }
    return selector;
  }

  /**
   * @dev read ERC20 destination
   * @param _data ERC20 transfert
   */
  function readERC20Destination(bytes memory _data) public pure returns (address) {
    address destination;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      destination := mload(add(_data, 0x24))
    }
    return destination;
  }

  /**
   * @dev read ERC20 value
   * @param _data contains the selector
   */
  function readERC20Value(bytes memory _data) public pure returns (uint256) {
    uint256 value;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      value := mload(add(_data, 0x44))
    }
    return value;
  }

  /**
   * @dev Modifier verifying that valid signatures are above _threshold
   */
  modifier thresholdRequired(
    bytes[] memory _signatures,
    address _destination, uint256 _value, bytes memory _data,
    uint256 _validity, uint8 _threshold)
  {
    require(
      reviewSignatures(
        _signatures, _destination, _value, _data, _validity
      ) >= _threshold,
      "MS01"
    );
    _;
  }

  /**
   * @dev Modifier verifying that transaction is still valid
   * @dev This modifier also protects against replay on forked chain.
   *
   * @notice If both the _validity and gasPrice are low, then there is a risk
   * @notice that the transaction is executed after its _validity but before it does timeout
   * @notice In that case, the transaction will fail.
   * @notice In general, it is recommended to use a _validity greater than the potential timeout
   */
  modifier stillValid(uint256 _validity)
  {
    if (_validity != 0) {
      require(_validity >= block.number, "MS02");
    }
    _;
  }

  /**
   * @dev Modifier requiring that the message sender belongs to the signers
   */
  modifier onlySigners() {
    bool found = false;
    for (uint256 i = 0; i < signers_.length && !found; i++) {
      found = (msg.sender == signers_[i]);
    }
    require(found, "MS03");
    _;
  }

  /**
   * @dev returns signers
   */
  function signers() public view returns (address[] memory) {
    return signers_;
  }

  /**
   * returns threshold
   */
  function threshold() public view returns (uint8) {
    return threshold_;
  }

  /**
   * @dev returns replayProtection
   */
  function replayProtection() public view returns (bytes32) {
    return replayProtection_;
  }

  /**
   * @dev returns nonce
   */
  function nonce() public view returns (uint256) {
    return nonce_;
  }

  /**
   * @dev returns the number of valid signatures
   */
  function reviewSignatures(
    bytes[] memory _signatures,
    address _destination, uint256 _value, bytes memory _data,
    uint256 _validity)
    public view returns (uint256)
  {
    return reviewSignaturesInternal(
      _signatures,
      _destination,
      _value,
      _data,
      _validity,
      signers_
    );
  }

  /**
   * @dev buildHash
   **/
  function buildHash(
    address _destination, uint256 _value,
    bytes memory _data, uint256 _validity)
    public view returns (bytes32)
  {
    // FIXME: web3/solidity behaves differently with empty bytes
    if (_data.length == 0) {
      return keccak256(
        abi.encode(
          _destination, _value, _validity, replayProtection_
        )
      );
    } else {
      return keccak256(
        abi.encode(
          _destination, _value, _data, _validity, replayProtection_
        )
      );
    }
  }

  /**
   * @dev recover the public address from the signatures
   **/
  function recoverAddress(
    bytes memory _signature,
    address _destination, uint256 _value,
    bytes memory _data, uint256 _validity)
    public view returns (address)
  {
    return _signature.recoverSigner(
      buildHash(
        _destination,
        _value,
        _data,
        _validity
      )
    );
  }

  /**
   * @dev execute a transaction if enough signatures are valid
   **/
  function execute(
    bytes[] memory _signatures,
    address payable _destination, uint256 _value, bytes memory _data, uint256 _validity)
    public virtual
    stillValid(_validity)
    thresholdRequired(_signatures, _destination, _value, _data, _validity, threshold_)
    returns (bool)
  {
    executeInternal(_destination, _value, _data);
    return true;
  }

  /**
   * @dev review signatures against a list of signers
   * Signatures must be provided in the same order as the list of signers
   * All provided signatures must be valid and correspond to one of the signers
   * returns the number of valid signatures
   * returns 0 if the inputs are inconsistent
   */
  function reviewSignaturesInternal(
    bytes[] memory _signatures,
    address _destination, uint256 _value, bytes memory _data, uint256 _validity,
    address[] memory _signers)
    internal view returns (uint256)
  {
    uint256 length = _signatures.length;
    if (length == 0 || length > _signers.length) {
      return 0;
    }

    uint256 validSigs = 0;
    address recovered = recoverAddress(
      _signatures[0],
      _destination, _value, _data, _validity);
    for (uint256 i = 0; i < _signers.length; i++) {
      if (_signers[i] == recovered) {
        validSigs++;
        if (validSigs < length) {
          recovered = recoverAddress(
            _signatures[validSigs],
            _destination,
            _value,
            _data,
            _validity
          );
        } else {
          break;
        }
      }
    }

    if (validSigs != length) {
      return 0;
    }

    return validSigs;
  }

  /**
   * @dev execute a transaction
   **/
  function executeInternal(address payable _destination, uint256 _value, bytes memory _data)
    internal virtual
  {
    updateReplayProtection();
    if (_data.length == 0) {
      _destination.transfer(_value);
    } else {
      // solhint-disable-next-line avoid-call-value, avoid-low-level-calls
      (bool success, ) = _destination.call{value: _value}(_data);
      require(success, "MS04");
    }
    emit Execution(_destination, _value, _data);
  }

  /**
   * @dev update replay protection
   * contract address is used to prevent replay between different contracts
   * block hash is used to prevent replay between branches
   * nonce is used to prevent replay within the contract
   **/
  function updateReplayProtection() internal {
    replayProtection_ = keccak256(
      abi.encodePacked(address(this), blockhash(block.number-1), nonce_));
    nonce_++;
  }

  event Execution(address to, uint256 value, bytes data);
}
