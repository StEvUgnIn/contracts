pragma solidity ^0.8.0;

import "./LockableSig.sol";


/**
 * @title VaultSig
 * @dev VaultSig contract
 * The vault restrict operation to ETH or ERC20 transfer only
 *
 * @author Cyril Lapinte - <cyril@openfiz.com>
 * SPDX-License-Identifier: MIT
 *
 * Error messages
 * VS01: there should be no ETH provided when data is found
 * VS02: this contract only accept data for ERC20 transfer
 */
contract VaultSig is LockableSig {

  bytes4 constant public ERC20_TRANSFER_SELECTOR = bytes4(
    keccak256("transfer(address,uint256)")
  );

  /**
   * @dev constructor
   */
  constructor(address[] memory _addresses, uint8 _threshold)
    LockableSig(_addresses, _threshold)
  {}  // solhint-disable-line no-empty-blocks

  /**
   * @dev receive function
   */
  receive() external override payable {}

  /**
   * @dev fallback function
   */
  fallback() external override payable {}

  /**
   * @dev execute the transaction
   */
  function execute(
    bytes[] memory _signatures,
    address payable _destination,
    uint256 _value,
    bytes memory _data,
    uint256 _validity)
    public override
    stillValid(_validity)
    thresholdRequired(_signatures,
      _destination, _value, _data, _validity, threshold_)
    returns (bool)
  {
    if (_data.length == 0) {
      executeInternal(_destination, _value, "");
    } else {
      require(_value == 0, "VS01");
      require(readSelector(_data) == ERC20_TRANSFER_SELECTOR, "VS02");
      executeInternal(_destination, 0, _data);
    }
    return true;
  }

  /**
   * @dev execute an ERC20 transfer
   */
  function transferERC20(
    bytes[] memory _signatures,
    address payable _token,
    address _destination,
    uint256 _value) public
    returns (bool)
  {
    return execute(
      _signatures,
      _token,
      0,
      abi.encodeWithSelector(
        ERC20_TRANSFER_SELECTOR, _destination, _value
      ),
      0
    );
  }

  /**
   * @dev execute a transfer
   */
  function transfer(
    bytes[] memory _signatures,
    address payable _destination,
    uint256 _value) public
    returns (bool)
  {
    return execute(
      _signatures,
      _destination,
      _value,
      "",
      0
    );
  }
}
