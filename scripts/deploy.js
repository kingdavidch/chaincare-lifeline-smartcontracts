const { ethers, upgrades } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("🚀 Starting ChainCare Smart Contracts Deployment...\n");

  // Get signers
  const [deployer] = await ethers.getSigners();
  console.log("📝 Deploying contracts with account:", deployer.address);
  
  const balance = await deployer.getBalance();
  console.log("💰 Account balance:", ethers.utils.formatEther(balance), "ETH");
  
  if (balance.lt(ethers.utils.parseEther("0.1"))) {
    console.log("⚠️  Warning: Low balance detected. Ensure sufficient funds for deployment.");
  }

  const deployedContracts = {};
  const network = await ethers.provider.getNetwork();
  console.log("🌐 Deploying to network:", network.name, "- Chain ID:", network.chainId);
  console.log("\n" + "=".repeat(60));

  try {
    // 1. Deploy HealthcareIdentity (foundational contract)
    console.log("\n1️⃣  Deploying HealthcareIdentity...");
    const HealthcareIdentity = await ethers.getContractFactory("HealthcareIdentity");
    const healthcareIdentity = await HealthcareIdentity.deploy();
    await healthcareIdentity.deployed();
    deployedContracts.HealthcareIdentity = healthcareIdentity.address;
    console.log("✅ HealthcareIdentity deployed to:", healthcareIdentity.address);

    // 2. Deploy PatientRecord
    console.log("\n2️⃣  Deploying PatientRecord...");
    const PatientRecord = await ethers.getContractFactory("PatientRecord");
    const patientRecord = await PatientRecord.deploy();
    await patientRecord.deployed();
    deployedContracts.PatientRecord = patientRecord.address;
    console.log("✅ PatientRecord deployed to:", patientRecord.address);

    // 3. Deploy InsuranceClaims
    console.log("\n3️⃣  Deploying InsuranceClaims...");
    const InsuranceClaims = await ethers.getContractFactory("InsuranceClaims");
    const insuranceClaims = await InsuranceClaims.deploy();
    await insuranceClaims.deployed();
    deployedContracts.InsuranceClaims = insuranceClaims.address;
    console.log("✅ InsuranceClaims deployed to:", insuranceClaims.address);

    // 4. Deploy PaymentSystem
    console.log("\n4️⃣  Deploying PaymentSystem...");
    const PaymentSystem = await ethers.getContractFactory("PaymentSystem");
    
    // Use environment variables for stablecoin configuration
    const defaultStablecoin = process.env.DEFAULT_STABLECOIN || "0xA0b86a33E6441d58a676d8f1ce3f34d7CbecCCdE"; // USDC
    const feeCollector = process.env.FEE_COLLECTOR_ADDRESS || deployer.address;
    
    const paymentSystem = await PaymentSystem.deploy(defaultStablecoin, feeCollector);
    await paymentSystem.deployed();
    deployedContracts.PaymentSystem = paymentSystem.address;
    console.log("✅ PaymentSystem deployed to:", paymentSystem.address);
    console.log("   📍 Default Stablecoin:", defaultStablecoin);
    console.log("   📍 Fee Collector:", feeCollector);

    // 5. Deploy PharmaceuticalSupplyChain
    console.log("\n5️⃣  Deploying PharmaceuticalSupplyChain...");
    const PharmaceuticalSupplyChain = await ethers.getContractFactory("PharmaceuticalSupplyChain");
    const pharmaSupplyChain = await PharmaceuticalSupplyChain.deploy();
    await pharmaSupplyChain.deployed();
    deployedContracts.PharmaceuticalSupplyChain = pharmaSupplyChain.address;
    console.log("✅ PharmaceuticalSupplyChain deployed to:", pharmaSupplyChain.address);

    // 6. Deploy ClinicAppointments
    console.log("\n6️⃣  Deploying ClinicAppointments...");
    const ClinicAppointments = await ethers.getContractFactory("ClinicAppointments");
    const clinicAppointments = await ClinicAppointments.deploy();
    await clinicAppointments.deployed();
    deployedContracts.ClinicAppointments = clinicAppointments.address;
    console.log("✅ ClinicAppointments deployed to:", clinicAppointments.address);

    // 7. Deploy ChainCareHub (orchestration contract)
    console.log("\n7️⃣  Deploying ChainCareHub...");
    const ChainCareHub = await ethers.getContractFactory("ChainCareHub");
    const chainCareHub = await ChainCareHub.deploy(
      patientRecord.address,
      insuranceClaims.address,
      paymentSystem.address,
      pharmaSupplyChain.address,
      healthcareIdentity.address,
      clinicAppointments.address
    );
    await chainCareHub.deployed();
    deployedContracts.ChainCareHub = chainCareHub.address;
    console.log("✅ ChainCareHub deployed to:", chainCareHub.address);

    console.log("\n" + "=".repeat(60));
    console.log("🎉 All contracts deployed successfully!");

    // Contract integration setup
    console.log("\n⚙️  Setting up contract integrations...");

    // Grant necessary roles for integration
    const CLAIMS_CONTRACT_ROLE = await paymentSystem.CLAIMS_CONTRACT_ROLE();
    await paymentSystem.grantRole(CLAIMS_CONTRACT_ROLE, insuranceClaims.address);
    console.log("✅ Granted CLAIMS_CONTRACT_ROLE to InsuranceClaims");

    const PAYMENT_PROCESSOR_ROLE = await paymentSystem.PAYMENT_PROCESSOR_ROLE();
    await paymentSystem.grantRole(PAYMENT_PROCESSOR_ROLE, chainCareHub.address);
    console.log("✅ Granted PAYMENT_PROCESSOR_ROLE to ChainCareHub");

    // Save deployment addresses
    const deploymentInfo = {
      network: network.name,
      chainId: network.chainId,
      deployer: deployer.address,
      timestamp: new Date().toISOString(),
      contracts: deployedContracts
    };

    const deploymentsDir = path.join(__dirname, "../deployments");
    if (!fs.existsSync(deploymentsDir)) {
      fs.mkdirSync(deploymentsDir, { recursive: true });
    }

    const deploymentFile = path.join(deploymentsDir, `${network.name}-${network.chainId}.json`);
    fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));
    console.log("💾 Deployment info saved to:", deploymentFile);

    // Display summary
    console.log("\n📋 DEPLOYMENT SUMMARY");
    console.log("=".repeat(60));
    console.log(`Network: ${network.name} (Chain ID: ${network.chainId})`);
    console.log(`Deployer: ${deployer.address}`);
    console.log(`Timestamp: ${deploymentInfo.timestamp}`);
    console.log("\n📄 Contract Addresses:");
    
    Object.entries(deployedContracts).forEach(([name, address]) => {
      console.log(`${name}: ${address}`);
    });

    console.log("\n🔗 Etherscan Links:");
    const etherscanBase = getEtherscanBase(network.chainId);
    if (etherscanBase) {
      Object.entries(deployedContracts).forEach(([name, address]) => {
        console.log(`${name}: ${etherscanBase}/address/${address}`);
      });
    }

    console.log("\n🎯 Next Steps:");
    console.log("1. Verify contracts on Etherscan");
    console.log("2. Set up additional stablecoins in PaymentSystem");
    console.log("3. Configure initial healthcare entities");
    console.log("4. Set up frontend integration");
    console.log("5. Initialize test data for development");

    // Gas usage summary
    const deploymentReceipts = await Promise.all([
      healthcareIdentity.deployTransaction.wait(),
      patientRecord.deployTransaction.wait(),
      insuranceClaims.deployTransaction.wait(),
      paymentSystem.deployTransaction.wait(),
      pharmaSupplyChain.deployTransaction.wait(),
      clinicAppointments.deployTransaction.wait(),
      chainCareHub.deployTransaction.wait()
    ]);

    const totalGasUsed = deploymentReceipts.reduce((sum, receipt) => sum.add(receipt.gasUsed), ethers.BigNumber.from(0));
    console.log("\n⛽ Gas Usage Summary:");
    console.log(`Total Gas Used: ${totalGasUsed.toString()}`);
    console.log(`Estimated Cost: ${ethers.utils.formatEther(totalGasUsed.mul(ethers.utils.parseUnits("20", "gwei")))} ETH`);

  } catch (error) {
    console.error("\n❌ Deployment failed:", error);
    process.exit(1);
  }
}

function getEtherscanBase(chainId) {
  const etherscanUrls = {
    1: "https://etherscan.io",
    5: "https://goerli.etherscan.io",
    11155111: "https://sepolia.etherscan.io",
    137: "https://polygonscan.com",
    80001: "https://mumbai.polygonscan.com",
    56: "https://bscscan.com",
    97: "https://testnet.bscscan.com"
  };
  return etherscanUrls[chainId];
}

// Handle script execution
if (require.main === module) {
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = { main };