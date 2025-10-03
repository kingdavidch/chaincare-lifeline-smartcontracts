# ChainCare Smart Contracts - Setup Guide

## Prerequisites

Before setting up the ChainCare smart contracts project, ensure you have the following installed on your system:

### Required Software

1. **Node.js** (v16.0.0 or higher)
   ```bash
   # Check your Node.js version
   node --version
   
   # If not installed, download from https://nodejs.org/
   # Or install via package manager:
   # macOS (using Homebrew)
   brew install node
   
   # Ubuntu/Debian
   sudo apt update
   sudo apt install nodejs npm
   
   # Windows (using Chocolatey)
   choco install nodejs
   ```

2. **Git**
   ```bash
   # Check if Git is installed
   git --version
   
   # If not installed:
   # macOS (using Homebrew)
   brew install git
   
   # Ubuntu/Debian
   sudo apt install git
   
   # Windows: Download from https://git-scm.com/
   ```

3. **VS Code** (Recommended IDE)
   - Download from https://code.visualstudio.com/
   - Install Solidity extension by Juan Blanco

## Project Setup

### 1. Clone the Repository

```bash
# Clone the ChainCare smart contracts repository
git clone https://github.com/kingdavidch/chaincare-lifeline-smartcontracts.git

# Navigate to the project directory
cd chaincare-lifeline-smartcontracts
```

### 2. Install Dependencies

```bash
# Install all project dependencies
npm install

# If you encounter permission issues on macOS/Linux:
sudo npm install

# Alternative: Use Yarn (if preferred)
yarn install
```

### 3. Project Structure Setup

Create the following directory structure:

```
chaincare-lifeline-smartcontracts/
├── contracts/                 # Smart contract files
│   ├── PatientRecord.sol
│   ├── InsuranceClaims.sol
│   ├── PaymentSystem.sol
│   ├── PharmaceuticalSupplyChain.sol
│   ├── HealthcareIdentity.sol
│   ├── ClinicAppointments.sol
│   └── ChainCareHub.sol
├── scripts/                   # Deployment scripts
├── test/                      # Test files
├── docs/                      # Documentation
├── .env.example              # Environment variables template
├── hardhat.config.js         # Hardhat configuration
├── package.json              # Project dependencies
├── README.md                 # Project documentation
└── .gitignore               # Git ignore rules
```

### 4. Move Smart Contracts to Contracts Folder

```bash
# Create contracts directory
mkdir contracts

# Move all .sol files to contracts directory
mv *.sol contracts/

# Verify the move
ls contracts/
```

## Development Environment Setup

### 1. Install Hardhat (Ethereum Development Environment)

```bash
# Install Hardhat locally
npm install --save-dev hardhat

# Initialize Hardhat project (if not already done)
npx hardhat
# Choose "Create an empty hardhat.config.js"
```

### 2. Create Hardhat Configuration

Create `hardhat.config.js`:

```javascript
require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      chainId: 1337
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 1337
    },
    // Add other networks as needed
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    gasPrice: 20
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};
```

### 3. Environment Variables Setup

Create `.env` file:

```bash
# Copy the example environment file
cp .env.example .env

# Edit the .env file with your configuration
nano .env
```

`.env` file contents:
```
# Network Configuration
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_PROJECT_ID
MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_INFURA_PROJECT_ID

# Private Key (DO NOT COMMIT TO GIT)
PRIVATE_KEY=your_private_key_here

# API Keys
ETHERSCAN_API_KEY=your_etherscan_api_key
INFURA_PROJECT_ID=your_infura_project_id

# Gas Reporting
REPORT_GAS=true

# Stablecoin Addresses (for production)
USDC_ADDRESS=0xa0b86a33e6441d58a676d8f1ce3f34d7cbecccde
USDT_ADDRESS=0xdac17f958d2ee523a2206206994597c13d831ec7
DAI_ADDRESS=0x6b175474e89094c44da98b954eedeac495271d0f
```

### 4. Create Deployment Scripts

Create `scripts/deploy.js`:

```javascript
const { ethers, upgrades } = require("hardhat");

async function main() {
  console.log("Deploying ChainCare Smart Contracts...");

  // Get signers
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Deploy HealthcareIdentity first (needed by other contracts)
  const HealthcareIdentity = await ethers.getContractFactory("HealthcareIdentity");
  const healthcareIdentity = await HealthcareIdentity.deploy();
  await healthcareIdentity.deployed();
  console.log("HealthcareIdentity deployed to:", healthcareIdentity.address);

  // Deploy PatientRecord
  const PatientRecord = await ethers.getContractFactory("PatientRecord");
  const patientRecord = await PatientRecord.deploy();
  await patientRecord.deployed();
  console.log("PatientRecord deployed to:", patientRecord.address);

  // Deploy other contracts...
  // Add deployment logic for other contracts

  console.log("All contracts deployed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

## Testing Setup

### 1. Create Test Directory

```bash
# Create test directory
mkdir test

# Create a basic test file
touch test/ChainCare.test.js
```

### 2. Basic Test Template

Create `test/ChainCare.test.js`:

```javascript
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ChainCare Smart Contracts", function () {
  let patientRecord, insuranceClaims, paymentSystem;
  let owner, patient, doctor, insurer;

  beforeEach(async function () {
    [owner, patient, doctor, insurer] = await ethers.getSigners();

    // Deploy contracts
    const PatientRecord = await ethers.getContractFactory("PatientRecord");
    patientRecord = await PatientRecord.deploy();
    await patientRecord.deployed();

    // Add more contract deployments as needed
  });

  describe("PatientRecord", function () {
    it("Should register a patient", async function () {
      await patientRecord.connect(patient).registerPatient(
        "encrypted_data",
        owner.address
      );
      
      // Add assertions
    });

    // Add more tests
  });

  // Add tests for other contracts
});
```

## Development Workflow

### 1. Compile Contracts

```bash
# Compile all smart contracts
npm run compile

# Or using Hardhat directly
npx hardhat compile
```

### 2. Run Tests

```bash
# Run all tests
npm test

# Run tests with gas reporting
npm run gas-report

# Run tests with coverage
npm run coverage
```

### 3. Deploy to Local Network

```bash
# Start local Hardhat network
npm run node

# In another terminal, deploy to local network
npm run deploy:local
```

### 4. Code Quality

```bash
# Lint Solidity files
npm run lint

# Fix linting issues
npm run lint:fix

# Format code
npm run prettier
```

## IDE Setup (VS Code)

### Recommended Extensions

1. **Solidity** by Juan Blanco
2. **Hardhat Solidity** by Nomic Foundation  
3. **Prettier - Code formatter**
4. **GitLens**
5. **Bracket Pair Colorizer**

### VS Code Settings

Create `.vscode/settings.json`:

```json
{
  "solidity.compileUsingRemoteVersion": "v0.8.19+commit.7dd6d404",
  "solidity.defaultCompiler": "remote",
  "editor.formatOnSave": true,
  "prettier.documentSelectors": ["**/*.sol"],
  "[solidity]": {
    "editor.defaultFormatter": "JuanBlanco.solidity"
  }
}
```

## Troubleshooting

### Common Issues and Solutions

1. **Permission Denied Error**
   ```bash
   sudo npm install
   # Or change npm permissions:
   npm config set prefix ~/.npm-global
   export PATH=~/.npm-global/bin:$PATH
   ```

2. **Out of Gas Error**
   ```bash
   # Increase gas limit in hardhat.config.js
   gas: 6000000
   ```

3. **Compilation Error**
   ```bash
   # Clean and recompile
   npm run clean
   npm run compile
   ```

4. **Network Connection Issues**
   ```bash
   # Check your RPC URL in .env
   # Verify your internet connection
   # Try different RPC provider
   ```

## Next Steps

1. **Review the Smart Contracts**: Familiarize yourself with each contract's functionality
2. **Run Tests**: Execute the test suite to ensure everything works
3. **Deploy to Testnet**: Deploy contracts to a test network
4. **Integration**: Start building frontend or other integrations
5. **Security Audit**: Consider professional security auditing for production

## Getting Help

- **Documentation**: Check the README.md for detailed contract information
- **Issues**: Report bugs on GitHub issues
- **Community**: Join blockchain development communities
- **Resources**: 
  - [Hardhat Documentation](https://hardhat.org/docs)
  - [OpenZeppelin Documentation](https://docs.openzeppelin.com/)
  - [Solidity Documentation](https://docs.soliditylang.org/)

## Security Considerations

⚠️ **Important Security Notes:**

1. **Never commit private keys** to version control
2. **Use environment variables** for sensitive data
3. **Test thoroughly** before deploying to mainnet
4. **Consider multi-signature wallets** for contract ownership
5. **Get professional security audits** for production deployments
6. **Keep dependencies updated** regularly
7. **Use proxy patterns** for upgradeable contracts when needed

---

🎉 **Congratulations!** You now have a complete development environment for the ChainCare smart contracts project!