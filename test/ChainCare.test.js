const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");

describe("ChainCare Smart Contracts Integration", function () {
  async function deployChainCareFixture() {
    // Get signers
    const [owner, patient, doctor, insurer, pharmacy, hospital] = await ethers.getSigners();

    // Deploy HealthcareIdentity
    const HealthcareIdentity = await ethers.getContractFactory("HealthcareIdentity");
    const healthcareIdentity = await HealthcareIdentity.deploy();

    // Deploy PatientRecord
    const PatientRecord = await ethers.getContractFactory("PatientRecord");
    const patientRecord = await PatientRecord.deploy();

    // Deploy InsuranceClaims
    const InsuranceClaims = await ethers.getContractFactory("InsuranceClaims");
    const insuranceClaims = await InsuranceClaims.deploy();

    // Deploy mock USDC for testing
    const MockUSDC = await ethers.getContractFactory("MockERC20");
    const mockUSDC = await MockUSDC.deploy("USD Coin", "USDC", 6);

    // Deploy PaymentSystem
    const PaymentSystem = await ethers.getContractFactory("PaymentSystem");
    const paymentSystem = await PaymentSystem.deploy(mockUSDC.address, owner.address);

    // Deploy PharmaceuticalSupplyChain
    const PharmaceuticalSupplyChain = await ethers.getContractFactory("PharmaceuticalSupplyChain");
    const pharmaSupplyChain = await PharmaceuticalSupplyChain.deploy();

    // Deploy ClinicAppointments
    const ClinicAppointments = await ethers.getContractFactory("ClinicAppointments");
    const clinicAppointments = await ClinicAppointments.deploy();

    // Deploy ChainCareHub
    const ChainCareHub = await ethers.getContractFactory("ChainCareHub");
    const chainCareHub = await ChainCareHub.deploy(
      patientRecord.address,
      insuranceClaims.address,
      paymentSystem.address,
      pharmaSupplyChain.address,
      healthcareIdentity.address,
      clinicAppointments.address
    );

    // Grant necessary roles
    const CLAIMS_CONTRACT_ROLE = await paymentSystem.CLAIMS_CONTRACT_ROLE();
    await paymentSystem.grantRole(CLAIMS_CONTRACT_ROLE, insuranceClaims.address);

    return {
      healthcareIdentity,
      patientRecord,
      insuranceClaims,
      paymentSystem,
      pharmaSupplyChain,
      clinicAppointments,
      chainCareHub,
      mockUSDC,
      owner,
      patient,
      doctor,
      insurer,
      pharmacy,
      hospital
    };
  }

  describe("Patient Registration and Medical Records", function () {
    it("Should register a patient successfully", async function () {
      const { patientRecord, patient } = await loadFixture(deployChainCareFixture);

      await patientRecord.connect(patient).registerPatient(
        "encrypted_personal_info",
        patient.address // Emergency contact
      );

      const isRegistered = await patientRecord.registeredPatients(patient.address);
      expect(isRegistered).to.be.true;
    });

    it("Should create medical record for registered patient", async function () {
      const { patientRecord, patient, doctor } = await loadFixture(deployChainCareFixture);

      // Register patient
      await patientRecord.connect(patient).registerPatient(
        "encrypted_personal_info",
        patient.address
      );

      // Grant access to doctor
      await patientRecord.connect(patient).grantAccess(doctor.address, "doctor");

      // Create medical record
      await patientRecord.connect(doctor).createMedicalRecord(
        patient.address,
        "encrypted_medical_data",
        "diagnosis",
        ["attachment1", "attachment2"]
      );

      const recordIds = await patientRecord.getPatientRecords(patient.address);
      expect(recordIds.length).to.equal(1);
    });
  });

  describe("Healthcare Identity Verification", function () {
    it("Should register and verify healthcare entity", async function () {
      const { healthcareIdentity, doctor } = await loadFixture(deployChainCareFixture);

      // Request verification
      await healthcareIdentity.connect(doctor).requestVerification(
        1, // EntityType.Doctor
        "Dr. John Smith",
        "MED12345",
        "California",
        ["license.pdf", "certification.pdf"],
        "encrypted_contact_info",
        10, // experience years
        "Cardiology"
      );

      // Process verification (as admin)
      await healthcareIdentity.processVerification(
        1, // request ID
        true, // approve
        "Verification completed successfully",
        ["Board Certified"]
      );

      const isRegistered = await healthcareIdentity.registeredEntities(doctor.address);
      expect(isRegistered).to.be.true;
    });
  });

  describe("Insurance Claims Processing", function () {
    it("Should create insurance policy and submit claim", async function () {
      const { insuranceClaims, patient, doctor, insurer } = await loadFixture(deployChainCareFixture);

      // Create insurance policy
      await insuranceClaims.connect(insurer).createInsurancePolicy(
        "POL123456",
        patient.address,
        ethers.utils.parseEther("10000"), // 10,000 coverage
        ethers.utils.parseEther("100"), // 100 deductible
        Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60, // 1 year expiry
        ["General Medicine", "Emergency Care"]
      );

      // Authorize provider
      await insuranceClaims.authorizeProvider(doctor.address, 60); // 5 years experience

      // Submit claim
      await insuranceClaims.connect(doctor).submitClaim(
        "POL123456",
        ethers.utils.parseEther("500"), // Claim amount
        "Pneumonia",
        "J18.9",
        ["chest_xray.pdf", "lab_results.pdf"],
        false, // not emergency
        1 // medical record ID
      );

      const providerClaims = await insuranceClaims.getProviderClaims(doctor.address);
      expect(providerClaims.length).to.equal(1);
    });
  });

  describe("Clinic Appointments", function () {
    it("Should register clinic and doctor, then book appointment", async function () {
      const { clinicAppointments, patient, doctor, hospital } = await loadFixture(deployChainCareFixture);

      // Register clinic
      await clinicAppointments.connect(hospital).registerClinic(
        "City General Hospital",
        "123 Medical St",
        ["General Medicine", "Emergency Care"],
        "contact@hospital.com",
        "08:00-17:00",
        ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
        ethers.utils.parseEther("0.1"), // 0.1 ETH consultation fee
        true // accepts insurance
      );

      // Register doctor to clinic
      await clinicAppointments.connect(hospital).registerDoctor(
        doctor.address,
        1, // clinic ID
        "Dr. Jane Smith",
        "General Medicine",
        "MED67890",
        ethers.utils.parseEther("0.1"), // consultation fee
        ["Monday", "Wednesday", "Friday"],
        ["09:00", "10:00", "11:00", "14:00", "15:00"],
        8, // experience years
        "MD, Board Certified"
      );

      // Create time slots
      await clinicAppointments.connect(doctor).createTimeSlots(
        doctor.address,
        "2025-10-15",
        ["09:00", "10:00", "11:00"],
        30, // 30 minutes duration
        ethers.utils.parseEther("0.1") // fee
      );

      // Book appointment
      await clinicAppointments.connect(patient).bookAppointment(
        doctor.address,
        1, // time slot ID
        0, // GeneralConsultation
        "Chest pain and shortness of breath",
        "Patient notes about symptoms",
        ["symptom_photo.jpg"],
        false // not emergency
      );

      const patientAppointments = await clinicAppointments.getPatientAppointments(patient.address);
      expect(patientAppointments.length).to.equal(1);
    });
  });

  describe("Pharmaceutical Supply Chain", function () {
    it("Should manufacture, ship, and dispense pharmaceutical product", async function () {
      const { pharmaSupplyChain, pharmacy, patient } = await loadFixture(deployChainCareFixture);

      // Authorize entities
      const MANUFACTURER_ROLE = await pharmaSupplyChain.MANUFACTURER_ROLE();
      const PHARMACY_ROLE = await pharmaSupplyChain.PHARMACY_ROLE();
      
      await pharmaSupplyChain.authorizeEntity(pharmacy.address, MANUFACTURER_ROLE);
      await pharmaSupplyChain.authorizeEntity(pharmacy.address, PHARMACY_ROLE);

      // Manufacture product
      await pharmaSupplyChain.connect(pharmacy).manufactureProduct(
        "BATCH001",
        "Amoxicillin",
        "Amoxicillin Trihydrate",
        1000, // quantity
        Math.floor(Date.now() / 1000) + 365 * 24 * 60 * 60, // 1 year expiry
        "Manufacturing Plant A",
        ["FDA Approved", "GMP Certified"],
        ethers.utils.parseEther("0.01"), // unit price
        "Store at room temperature"
      );

      // Dispense to patient
      await pharmaSupplyChain.connect(pharmacy).dispenseProduct(
        1, // product ID
        10, // quantity
        patient.address,
        "PRESCRIPTION123"
      );

      const product = await pharmaSupplyChain.getProduct(1);
      expect(product.quantity).to.equal(990); // 1000 - 10 dispensed
    });
  });

  describe("Integrated Workflows", function () {
    it("Should complete end-to-end patient journey", async function () {
      const { 
        chainCareHub, 
        patientRecord, 
        clinicAppointments, 
        patient, 
        doctor, 
        hospital 
      } = await loadFixture(deployChainCareFixture);

      // Setup: Register patient
      await patientRecord.connect(patient).registerPatient(
        "encrypted_personal_info",
        patient.address
      );

      // Setup: Register clinic and doctor
      await clinicAppointments.connect(hospital).registerClinic(
        "Test Clinic",
        "Test Location",
        ["General Medicine"],
        "test@clinic.com",
        "08:00-17:00",
        ["Monday", "Tuesday", "Wednesday"],
        ethers.utils.parseEther("0.1"),
        true
      );

      await clinicAppointments.connect(hospital).registerDoctor(
        doctor.address,
        1,
        "Dr. Test",
        "General Medicine",
        "TEST123",
        ethers.utils.parseEther("0.1"),
        ["Monday", "Tuesday"],
        ["09:00", "10:00"],
        5,
        "MD"
      );

      await clinicAppointments.connect(doctor).createTimeSlots(
        doctor.address,
        "2025-10-15",
        ["09:00"],
        30,
        ethers.utils.parseEther("0.1")
      );

      // Test integrated booking
      await chainCareHub.connect(patient).bookConsultationAndCreateRecord(
        doctor.address,
        1, // time slot ID
        "Test symptoms",
        "Test patient notes",
        0 // GeneralConsultation
      );

      // Verify appointment was created
      const appointments = await clinicAppointments.getPatientAppointments(patient.address);
      expect(appointments.length).to.equal(1);
    });
  });
});

// Mock ERC20 contract for testing
const MockERC20 = {
  deploy: async function(name, symbol, decimals) {
    const MockToken = await ethers.getContractFactory("MockERC20");
    return await MockToken.deploy(name, symbol, decimals);
  }
};