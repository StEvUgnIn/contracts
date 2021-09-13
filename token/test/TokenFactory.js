'user strict';

/**
 * @author Cyril Lapinte - <cyril.lapinte@openfiz.com>
 */

const assertRevert = require('./helpers/assertRevert');
const assertGasEstimate = require('./helpers/assertGasEstimate');
const TokenDelegate = artifacts.require('TokenDelegate.sol');
const TokenCore = artifacts.require('TokenCore.sol');
const TokenFactory = artifacts.require('TokenFactory.sol');
const TokenProxy = artifacts.require('TokenProxy.sol');
const WrappedERC20 = artifacts.require('WrappedERC20Mock.sol');

const TOKEN_DEPLOYMENT_COST = 1269301;
const TRANSFER_OK = 1;
const TRANSFER_LOCKED = 5;
const TRANSFER_RULED = 7;

const NULL_ADDRESS = '0x'.padEnd(42, '0');
const NAME = 'Token';
const SYMBOL = 'TKN';
const DECIMALS = 18;
const LOCK_END = '' + Math.floor((new Date().getTime() + 3600 * 24 * 365 * 1000) / 1000);
const SUPPLIES_DECIMALS = '000000000000000000';
const SUPPLIES = [42 * 10 ** 6 + SUPPLIES_DECIMALS, 24 * 10 ** 6 + SUPPLIES_DECIMALS];
const TOTAL_SUPPLY = 66 * 10 ** 6 + SUPPLIES_DECIMALS;
const END_OF_TIME = '18446744073709551615';

const ALL_PROXIES = web3.utils.toChecksumAddress(
  '0x' + web3.utils.fromAscii('AllProxies').substr(2).padStart(40, '0'));
const ANY_ADDRESSES = web3.utils.toChecksumAddress(
  '0x' + web3.utils.fromAscii('AnyAddresses').substr(2).padStart(40, '0'));

const REQUIRED_CORE_PRIVILEGES = [
  web3.utils.sha3('assignProxyOperators(address,bytes32,address[])'),
  web3.utils.sha3('defineToken(address,uint256,string,string,uint256)'),
  web3.utils.sha3('defineAuditTriggers(uint256,address[],address[],uint8[])'),
].map((x) => x.substr(0, 10));
const REQUIRED_PROXY_PRIVILEGES = [
  web3.utils.sha3('mint(address,address[],uint256[])'),
  web3.utils.sha3('finishMinting(address)'),
  web3.utils.sha3('defineLock(address,address,address,uint64,uint64)'),
  web3.utils.sha3('defineTokenLocks(address,address[])'),
  web3.utils.sha3('defineRules(address,address[])'),
].map((x) => x.substr(0, 10));
const APPROVE_PRIVILEGES = [
  web3.utils.sha3('approveToken(address,address)'),
].map((x) => x.substr(0, 10));
const ISSUER_PRIVILEGES = [
  web3.utils.sha3('configureTokensales(address,address[],uint256[])'),
  web3.utils.sha3('updateAllowances(address,address[],uint256[])'),
  web3.utils.sha3('deployWrappedToken(address,string,string,uint256,address[],uint256[],bool)'),
].map((x) => x.substr(0, 10));
const OPERATOR_PRIVILEGES = [
  web3.utils.sha3('transferFrom(address,address,address,uint256)'),
].map((x) => x.substr(0, 10));
const FACTORY_CORE_ROLE = web3.utils.fromAscii('FactoryCoreRole').padEnd(66, '0');
const FACTORY_PROXY_ROLE = web3.utils.fromAscii('FactoryProxyRole').padEnd(66, '0');
const ISSUER_PROXY_ROLE = web3.utils.fromAscii('IssuerProxyRole').padEnd(66, '0');
const APPROVER_PROXY_ROLE = web3.utils.fromAscii('ApproverProxyRole').padEnd(66, '0');
const OPERATOR_PROXY_ROLE = web3.utils.fromAscii('OperatorProxyRole').padEnd(66, '0');

contract('TokenFactory', function (accounts) {
  let proxyCode, proxyCodeHash;
  let delegate, core, factory;

  const VAULTS = [accounts[2], accounts[3]];

  beforeEach(async function () {
    delegate = await TokenDelegate.new();
    core = await TokenCore.new('MyCore', [accounts[0]]);
    await core.defineTokenDelegate(1, delegate.address, [0, 1]);
    factory = await TokenFactory.new();

    proxyCode = TokenProxy.bytecode;
    proxyCodeHash = web3.utils.sha3(proxyCode);
  });

  it('should prevent non authorized to define a blueprint', async function () {
    await assertRevert(factory.defineBlueprint(
      0, NULL_ADDRESS, proxyCode, '0x', { from: accounts[1] }), 'OP01');
  });

  it('should let operator define a blueprint', async function () {
    const tx = await factory.defineBlueprint(0, NULL_ADDRESS, proxyCode, '0x');
    assert.ok(tx.receipt.status, 'Status');
    assert.equal(tx.logs.length, 1);
    assert.equal(tx.logs[0].event, 'BlueprintDefined', 'event');
    assert.equal(tx.logs[0].args.codeHash, proxyCodeHash, 'proxy codeHash');
  });

  it('should prevent factory to deploy a token without core access', async function () {
    await assertRevert(factory.deployToken(
      core.address, 1, NAME, SYMBOL, DECIMALS, LOCK_END, false,
      [accounts[0], factory.address], SUPPLIES, [accounts[0]]), 'TF01');
  });

  it('should not have core access', async function () {
    const access = await factory.hasCoreAccess(core.address);
    assert.ok(!access, 'not access');
  });

  it('should have required core privileges', async function () {
    const requiredCorePrivileges =
      await Promise.all(REQUIRED_CORE_PRIVILEGES.map(
        (_, i) => factory.requiredCorePrivileges(i)));
    assert.deepEqual(requiredCorePrivileges, REQUIRED_CORE_PRIVILEGES, 'core privileges');
    await assertRevert(factory.requiredCorePrivileges(REQUIRED_CORE_PRIVILEGES.length));
  });

  it('should have required proxy privileges', async function () {
    const requiredProxyPrivileges =
      await Promise.all(REQUIRED_PROXY_PRIVILEGES.map(
        (_, i) => factory.requiredProxyPrivileges(i)));
    assert.deepEqual(requiredProxyPrivileges, REQUIRED_PROXY_PRIVILEGES, 'proxy privileges');
    await assertRevert(factory.requiredProxyPrivileges(REQUIRED_PROXY_PRIVILEGES.length));
  });

  describe('With proxy code defined and core authorizations', function () {
    beforeEach(async function () {
      await factory.defineBlueprint(0, NULL_ADDRESS, proxyCode, '0x');
      await core.defineRole(FACTORY_CORE_ROLE, REQUIRED_CORE_PRIVILEGES);
      await core.assignOperators(FACTORY_CORE_ROLE, [factory.address]);
      await core.defineRole(FACTORY_PROXY_ROLE, REQUIRED_PROXY_PRIVILEGES);
      await core.assignProxyOperators(ALL_PROXIES, FACTORY_PROXY_ROLE, [factory.address]);
    });

    it('should have core access', async function () {
      const access = await factory.hasCoreAccess(core.address);
      assert.ok(access, 'access');
    });

    it('should estimate a new token deployment [ @skip-on-coverage ]', async function () {
      const gasCost = await factory.deployToken.estimateGas(
        core.address, 1, NAME, SYMBOL, DECIMALS, LOCK_END, true,
        VAULTS, SUPPLIES, [accounts[0]]);
      assertGasEstimate(gasCost, TOKEN_DEPLOYMENT_COST, 'gas cost');
    });

    it('should deploy a new token', async function () {
      const tx = await factory.deployToken(
        core.address, 1, NAME, SYMBOL, DECIMALS, LOCK_END, true,
        VAULTS, SUPPLIES, [accounts[0]]);
      assert.ok(tx.receipt.status, 'Status');
      assert.equal(tx.logs.length, 2, 'logs');
      assert.equal(tx.logs[0].event, 'ContractDeployed', 'event');
      assert.equal(tx.logs[0].args.address_.length, 42, 'proxy address length');
      assert.ok(tx.logs[1].args.address_ !== NULL_ADDRESS, 'proxy address not null');
      assert.equal(tx.logs[1].event, 'TokenDeployed', 'event');
      assert.equal(tx.logs[1].args.token.length, 42, 'proxy address length');
      assert.ok(tx.logs[1].args.token !== NULL_ADDRESS, 'proxy address not null');
    });

    it('should deploy a contract', async function () {
      const coreParameter =
        '0x' + core.address.substr(2).padStart(64, '0').toLowerCase();
      const tx = await factory.deployContract(0, coreParameter);
      assert.ok(tx.receipt.status, 'Status');
      assert.equal(tx.logs.length, 1, 'logs');
      assert.equal(tx.logs[0].event, 'ContractDeployed', 'event');
      assert.equal(tx.logs[0].args.address_.length, 42, 'proxy address length');
      assert.ok(tx.logs[0].args.address_ !== NULL_ADDRESS, 'proxy address not null');
    });

    describe('With a token deployed by a non operator without lock', function () {
      let token;

      beforeEach(async function () {
        const tx = await factory.deployToken(
          core.address, 1, NAME, SYMBOL, DECIMALS, 0, true,
          [factory.address, factory.address], SUPPLIES, [accounts[1]], { from: accounts[1] });
        const tokenAddress = tx.logs[0].args.address_;
        token = await TokenProxy.at(tokenAddress);
      });

      it('should have a token', async function () {
        const name = await token.name();
        assert.equal(name, NAME, 'name');
        const symbol = await token.symbol();
        assert.equal(symbol, SYMBOL, 'symbol');
        const decimals = await token.decimals();
        assert.equal(decimals, DECIMALS, 'decimals');
        const totalSupply = await token.totalSupply();
        assert.equal(totalSupply.toString(), TOTAL_SUPPLY, 'total supply');
      });

      it('should have roles defined', async function () {
        const issuerRole = await core.proxyRole(token.address, accounts[1]);
        assert.equal(issuerRole, ISSUER_PROXY_ROLE, 'issuer role');
      });

      it('should have token data', async function () {
        const tokenData = await core.token(token.address);
        assert.ok(tokenData.mintingFinished, 'mintingFinished');
        assert.equal(tokenData.allTimeMinted.toString(), TOTAL_SUPPLY, 'all time minted');
        assert.equal(tokenData.allTimeBurned.toString(), 0, 'all time burned');
        assert.equal(tokenData.allTimeSeized.toString(), 0, 'all time seized');
        assert.deepEqual(tokenData.locks, [token.address], 'locks');
        assert.deepEqual(tokenData.rules, [factory.address], 'rules');
      });

      it('should have token locked', async function () {
        const lockData = await core.lock(token.address, ANY_ADDRESSES, ANY_ADDRESSES);
        assert.equal(lockData.startAt.toString(), '0', 'startAt');
        assert.equal(lockData.endAt.toString(), '0', 'endAt');
      });

      it('should return canTransfer tokens', async function () {
        const canTransfer = await token.canTransfer.call(accounts[2], accounts[0], 1);
        assert.equal(canTransfer.toString(), TRANSFER_RULED, 'canTransfer locked');
      });

      it('should not be possible to transfer tokens', async function () {
        await assertRevert(token.transfer(accounts[0], 1, { from: accounts[2] }), 'CT03');
      });
    });

    describe('With a token deployed by a compliance operator', function () {
      let token;

      beforeEach(async function () {
        const tx = await factory.deployToken(
          core.address, 1, NAME, SYMBOL, DECIMALS, LOCK_END, true,
          [factory.address, accounts[2]], SUPPLIES, [accounts[0]]);
        const tokenAddress = tx.logs[0].args.address_;
        token = await TokenProxy.at(tokenAddress);
      });

      it('should have a token', async function () {
        const name = await token.name();
        assert.equal(name, NAME, 'name');
        const symbol = await token.symbol();
        assert.equal(symbol, SYMBOL, 'symbol');
        const decimals = await token.decimals();
        assert.equal(decimals, DECIMALS, 'decimals');
        const totalSupply = await token.totalSupply();
        assert.equal(totalSupply.toString(), TOTAL_SUPPLY, 'total supply');
      });

      it('should have roles defined', async function () {
        const issuerRole = await core.proxyRole(token.address, accounts[0]);
        assert.equal(issuerRole, ISSUER_PROXY_ROLE, 'issuer role');
      });

      it('should have token data', async function () {
        const tokenData = await core.token(token.address);
        assert.ok(tokenData.mintingFinished, 'mintingFinished');
        assert.equal(tokenData.allTimeMinted.toString(), TOTAL_SUPPLY, 'all time minted');
        assert.equal(tokenData.allTimeBurned.toString(), 0, 'all time burned');
        assert.equal(tokenData.allTimeSeized.toString(), 0, 'all time seized');
        assert.deepEqual(tokenData.locks, [token.address], 'locks');
        assert.deepEqual(tokenData.rules, [], 'rules');
      });

      it('should have token locked', async function () {
        const lockData = await core.lock(token.address, ANY_ADDRESSES, ANY_ADDRESSES);
        assert.equal(lockData.startAt.toString(), '0', 'startAt');
        assert.equal(lockData.endAt.toString(), LOCK_END, 'endAt');
      });

      it('should return canTransfer tokens', async function () {
        const canTransfer = await token.canTransfer.call(accounts[2], accounts[0], 1);
        assert.equal(canTransfer.toString(), TRANSFER_LOCKED, 'canTransfer locked');
      });

      it('should not be possible to transfer tokens', async function () {
        await assertRevert(token.transfer(accounts[0], 1, { from: accounts[2] }), 'CT01');
      });

      it('should not let non proxy operator to approve token', async function () {
        await assertRevert(factory.approveToken(core.address,
          token.address, { from: accounts[1] }), 'OA01');
      });

      it('should not let non proxy operator to configure tokensale', async function () {
        await assertRevert(factory.configureTokensales(token.address, [], []), 'OA02');
      });

      it('should not let non proxy operator to deploy a wrapped token', async function () {
        await assertRevert(factory.deployWrappedToken(token.address,
          'Wrapped Token', 'wTOK', 18,
          [accounts[0], accounts[1]],
          ['150000', '200000'], true), 'OA02');
      });

      it('should not let non proxy operator to update allowances', async function () {
        await assertRevert(factory.updateAllowances(token.address, [], []), 'OA02');
      });

      describe('With approver authorizations', function () {
        beforeEach(async function () {
          await core.defineRole(APPROVER_PROXY_ROLE, APPROVE_PRIVILEGES);
          await core.assignOperators(APPROVER_PROXY_ROLE, [accounts[1]]);
        });

        it('should let approver approve token with no selectors', async function () {
          const tx = await factory.approveToken(core.address,
            token.address, { from: accounts[1] });
          assert.ok(tx.receipt.status, 'Status');
          assert.equal(tx.logs.length, 1);
          assert.equal(tx.logs[0].event, 'TokenApproved', 'event');
          assert.equal(tx.logs[0].args.token, token.address, 'token');
        });

        it('should let approver approve token with selectors', async function () {
          const tx = await factory.approveToken(core.address,
            token.address, { from: accounts[1] });
          assert.ok(tx.receipt.status, 'Status');
          assert.equal(tx.logs.length, 1);
          assert.equal(tx.logs[0].event, 'TokenApproved', 'event');
          assert.equal(tx.logs[0].args.token, token.address, 'token');
        });
      });

      describe('With issuer authorizations', function () {
        beforeEach(async function () {
          await core.defineRole(ISSUER_PROXY_ROLE, ISSUER_PRIVILEGES);
        });

        it('should let issuer configure tokensales with no tokensales', async function () {
          const tx = await factory.configureTokensales(token.address, [], []);
          assert.ok(tx.receipt.status, 'Status');
          assert.equal(tx.logs.length, 1);
          assert.equal(tx.logs[0].event, 'TokensalesConfigured', 'event');
          assert.equal(tx.logs[0].args.token, token.address, 'token');
          assert.deepEqual(tx.logs[0].args.tokensales, [], 'tokensales');
        });

        it('should let issuer configure tokensales with tokensales', async function () {
          const tx = await factory.configureTokensales(token.address,
            [accounts[1], accounts[2]], ['10000', '20000']);
          assert.ok(tx.receipt.status, 'Status');
          assert.equal(tx.logs.length, 3);
          assert.equal(tx.logs[2].event, 'TokensalesConfigured', 'event');
          assert.equal(tx.logs[2].args.token, token.address, 'token');
          assert.deepEqual(tx.logs[2].args.tokensales, [accounts[1], accounts[2]], 'tokensales');
        });

        describe('with tokensale configured', function () {
          beforeEach(async function () {
            await factory.configureTokensales(token.address,
              [accounts[1], accounts[2]], ['10000', '20000']);
          });

          it('should have token locked for tokensale 1', async function () {
            const lockData = await core.lock(token.address, accounts[1], ANY_ADDRESSES);
            assert.equal(lockData.startAt.toString(), END_OF_TIME, 'startAt');
            assert.equal(lockData.endAt.toString(), END_OF_TIME, 'endAt');
          });

          it('should have token locked for tokensale 2', async function () {
            const lockData = await core.lock(token.address, accounts[2], ANY_ADDRESSES);
            assert.equal(lockData.startAt.toString(), END_OF_TIME, 'startAt');
            assert.equal(lockData.endAt.toString(), END_OF_TIME, 'endAt');
          });

          it('should return canTransfer tokens', async function () {
            const canTransfer = await token.canTransfer.call(accounts[2], accounts[0], 1);
            assert.equal(canTransfer.toString(), TRANSFER_OK, 'canTransfer locked');
          });
        });

        it('should let issuer update allowances with no spenders', async function () {
          const tx = await factory.updateAllowances(token.address, [], []);
          assert.ok(tx.receipt.status, 'Status');
          assert.equal(tx.logs.length, 0);
        });

        it('should let issuer update allowance with spenders', async function () {
          const tx = await factory.updateAllowances(token.address,
            [accounts[1], accounts[2]], ['0', '100000']);
          assert.ok(tx.receipt.status, 'Status');
          assert.equal(tx.logs.length, 2);
          assert.equal(tx.logs[0].event, 'AllowanceUpdated', 'event1');
          assert.equal(tx.logs[0].args.token, token.address, 'token1');
          assert.equal(tx.logs[0].args.spender, accounts[1], 'spender1');
          assert.equal(tx.logs[0].args.allowance, '0', 'allowance1');
          assert.equal(tx.logs[1].event, 'AllowanceUpdated', 'event2');
          assert.equal(tx.logs[1].args.token, token.address, 'token2');
          assert.equal(tx.logs[1].args.spender, accounts[2], 'spender2');
          assert.equal(tx.logs[1].args.allowance, '100000', 'allowance2');
        });
      });
    });

    describe('With a C-Layer token deployed, approved and roles configured', function () {
      let token;
      let wrappedCode;

      beforeEach(async function () {
        wrappedCode = WrappedERC20.bytecode;
        await factory.defineBlueprint(1, NULL_ADDRESS, wrappedCode, '0x');

        const tx = await factory.deployToken(
          core.address, 1, NAME, SYMBOL, DECIMALS, 0, true,
          [factory.address, accounts[1]], SUPPLIES, [accounts[0]]);
        const tokenAddress = tx.logs[0].args.address_;
        token = await TokenProxy.at(tokenAddress);

        await core.defineRole(ISSUER_PROXY_ROLE, ISSUER_PRIVILEGES);
        await core.defineRole(OPERATOR_PROXY_ROLE, OPERATOR_PRIVILEGES);

        await core.defineRole(APPROVER_PROXY_ROLE, APPROVE_PRIVILEGES);
        await core.assignOperators(APPROVER_PROXY_ROLE, [accounts[1]]);
        await factory.approveToken(core.address, token.address, { from: accounts[1] });
      });

      it('should let deploy a wrapped token without compliance', async function () {
        const tx = await factory.deployWrappedToken(token.address,
          'Wrapped Token', 'wTOK', 18,
          [accounts[0], accounts[1]],
          [10 ** 6 + SUPPLIES_DECIMALS, 10 ** 6 + SUPPLIES_DECIMALS], false);
        assert.ok(tx.receipt.status, 'Status');
        assert.equal(tx.logs.length, 2);

        assert.equal(tx.logs[0].event, 'ContractDeployed', 'event1');
        assert.ok(tx.logs[0].args.address_ !== NULL_ADDRESS, 'wToken');

        assert.equal(tx.logs[1].event, 'WrappedTokenDeployed', 'event1');
        assert.equal(tx.logs[1].args.token, token.address, 'token');
        assert.ok(tx.logs[1].args.wrapped !== NULL_ADDRESS, 'wrapped');
      });

      it('should let deploy a wrapped token with compliance', async function () {
        const tx = await factory.deployWrappedToken(token.address,
          'Wrapped Token', 'wTOK', 18,
          [accounts[0], accounts[1]],
          [10 ** 6 + SUPPLIES_DECIMALS, 10 ** 6 + SUPPLIES_DECIMALS], true);

        assert.ok(tx.receipt.status, 'Status');
        assert.equal(tx.logs.length, 2);

        assert.equal(tx.logs[0].event, 'ContractDeployed', 'event1');
        assert.ok(tx.logs[0].args.address_ !== NULL_ADDRESS, 'wToken');

        assert.equal(tx.logs[1].event, 'WrappedTokenDeployed', 'event1');
        assert.equal(tx.logs[1].args.token, token.address, 'token');
        assert.ok(tx.logs[1].args.wrapped !== NULL_ADDRESS, 'wrapped');
      });
    });
  });
});
