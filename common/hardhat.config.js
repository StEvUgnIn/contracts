const fs = require('fs');
const path = require('path');

require('@nomiclabs/hardhat-truffle5');
require('@nomiclabs/hardhat-solhint');
require('solidity-coverage');
require('hardhat-gas-reporter');
require('hardhat-tracer');

let secret = {
  mnemonic: 'test test test test test test test test test test test junk',
  projectId: '',
};

/*
task('accounts', 'Prints the list of accounts', async (taskArgs, hre) => {
  const accounts = await hre.web3.eth.getAccounts().then(async (accounts) =>
    await Promise.all(accounts.map(async (account) => {
      const balance = await hre.web3.eth.getBalance(account);
      return {
        address: account,
        balance: await hre.web3.eth.getBalance(account),
      };
    }))
  );

  for (const account of accounts) {
    console.log(account.address + ' : ' + hre.web3.utils.fromWei(account.balance, 'ether') + ' ETH');
  }
});
*/

try {
  // Secret file format is:
  // { mnemonic: '', projectId, '', endpoints: { <networkname>: 'http://endpoint' } }

  const secretFiles = [ '~/.secret.json', '../.secret.json', '../../.secret.json', '../../../.secret.json' ];
  for (let i = 0; i < secretFiles.length; i++) {
    if (fs.existsSync(secretFiles[i])) {
      secret = JSON.parse(fs.readFileSync(secretFiles[i]));
      break;
    }
  }

  const secretFile = path.join(__dirname, '.secret.json');
  if (fs.existsSync(secretFile)) {
    secret = JSON.parse(fs.readFileSync(secretFile));
  }
} catch (warning) {
  console.warn('Unable to find secret configuration:', warning);
}

const enableGasReport = !!process.env.ENABLE_GAS_REPORT;

const config = {
  solidity: {
    version: '0.8.7',
    settings: {
      optimizer: {
        enabled: true,
        runs: 10000,
      },
    },
  },
  networks: {
    hardhat: {
      blockGasLimit: 10000000,
    },
    ropsten: {
      url: 'https://ropsten.infura.io/v3/' + secret.projectId,
      chainId: 3,
      gas: 'auto',
      accounts: {
        mnemonic: secret.mnemonic,
      },
    },
    rinkeby: {
      url: 'https://rinkeby.infura.io/v3/' + secret.projectId,
      chainId: 4,
      gas: 'auto',
      accounts: {
        mnemonic: secret.mnemonic,
      },
    },
    goerli: {
      url: 'https://goerli.infura.io/v3/' + secret.projectId,
      chainId: 5,
      gas: 'auto',
      accounts: {
        mnemonic: secret.mnemonic,
      },
    },
    kovan: {
      url: 'https://kovan.infura.io/v3/' + secret.projectId,
      chainId: 42,
      gas: 'auto',
      accounts: {
        mnemonic: secret.mnemonic,
      },
    },
    mainnet: {
      url: 'https://mainnet.infura.io/v3/' + secret.projectId,
      chainId: 1,
      gas: 'auto',
      accounts: {
        mnemonic: secret.mnemonic,
      },
    },
    arbitrumRinkeby: {
      url: 'https://rinkeby.arbitrum.io/rpc',
      chainId: 421611,
      gas: 'auto',
      accounts: {
        mnemonic: secret.mnemonic,
      },
    },
  },
  gasReporter: {
    enable: enableGasReport,
    currency: 'CHF',
    outputFile: process.env.CI ? 'gas-report.txt' : undefined,
  },
};

if (secret.endpoints) {
  // Injecting endpoints
  Object.keys(secret.endpoints).forEach((name) => {
    if (!config.networks[name]) {
      let template = {
        chainId: 9999,
        gas: 'auto',
      };
      Object.keys(config.networks).forEach((existingNetworkName) => {
        if (name.startsWith(existingNetworkName)) {
          template = config.networks[existingNetworkName];
        }
      });
      template.accounts = {
        mnemonic: secret.mnemonic,
      };
      template.url = secret.endpoints[name];
      config.networks[name] = template;
    }
  });
}

module.exports = config;
