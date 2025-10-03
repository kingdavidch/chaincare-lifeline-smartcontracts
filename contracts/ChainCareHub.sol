// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PatientRecord.sol";
import "./InsuranceClaims.sol";
import "./PaymentSystem.sol";
import "./PharmaceuticalSupplyChain.sol";
import "./HealthcareIdentity.sol";
import "./ClinicAppointments.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ChainCareHub
 * @dev Main orchestration contract for the ChainCare ecosystem
 * Coordinates interactions between all ChainCare smart contracts
 */
contract ChainCareHub is AccessControl {
    
    bytes32 public constant SYSTEM_ADMIN_ROLE = keccak256("SYSTEM_ADMIN_ROLE");
    bytes32 public constant INTEGRATION_ROLE = keccak256("INTEGRATION_ROLE");

    // Contract addresses
    PatientRecord public patientRecordContract;
    InsuranceClaims public insuranceClaimsContract;
    PaymentSystem public paymentSystemContract;
    PharmaceuticalSupplyChain public pharmaSupplyChainContract;
    HealthcareIdentity public healthcareIdentityContract;
    ClinicAppointments public clinicAppointmentsContract;

    // System configuration
    struct SystemConfig {
        bool isMaintenanceMode;
        uint256 maxTransactionsPerBlock;
        uint256 emergencyContactDelay;
        string systemVersion;
        address emergencyContact;
    }

    SystemConfig public systemConfig;

    // Integration events
    event ClaimSubmittedAndProcessed(
        uint256 indexed claimId,
        address indexed patient,
        address indexed provider,
        uint256 amount,
        bool autoApproved
    );
    event PaymentExecutedForClaim(
        uint256 indexed claimId,
        uint256 indexed paymentId,
        address indexed recipient,
        uint256 amount
    );
    event MedicalRecordLinkedToClaim(
        uint256 indexed recordId,
        uint256 indexed claimId,
        address indexed patient
    );
    event PrescriptionDispensed(
        uint256 indexed productId,
        uint256 indexed recordId,
        address indexed patient,
        address pharmacy
    );
    event AppointmentBookedWithRecord(
        uint256 indexed appointmentId,
        address indexed patient,
        address indexed doctor,
        string symptoms
    );
    event ConsultationCompletedWithRecord(
        uint256 indexed appointmentId,
        address indexed patient,
        address indexed doctor
    );
    event EmergencyConsultationBooked(
        address indexed patient,
        address indexed doctor,
        string symptoms
    );
    event SystemConfigUpdated(string parameter, string newValue);

    modifier onlyMaintenanceMode() {
        require(systemConfig.isMaintenanceMode, "System not in maintenance mode");
        _;
    }

    modifier notInMaintenanceMode() {
        require(!systemConfig.isMaintenanceMode, "System in maintenance mode");
        _;
    }

    constructor(
        address _patientRecord,
        address _insuranceClaims,
        address _paymentSystem,
        address _pharmaSupplyChain,
        address _healthcareIdentity,
        address _clinicAppointments
    ) {
        require(_patientRecord != address(0), "Invalid PatientRecord address");
        require(_insuranceClaims != address(0), "Invalid InsuranceClaims address");
        require(_paymentSystem != address(0), "Invalid PaymentSystem address");
        require(_pharmaSupplyChain != address(0), "Invalid PharmaSupplyChain address");
        require(_healthcareIdentity != address(0), "Invalid HealthcareIdentity address");
        require(_clinicAppointments != address(0), "Invalid ClinicAppointments address");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SYSTEM_ADMIN_ROLE, msg.sender);

        patientRecordContract = PatientRecord(_patientRecord);
        insuranceClaimsContract = InsuranceClaims(_insuranceClaims);
        paymentSystemContract = PaymentSystem(_paymentSystem);
        pharmaSupplyChainContract = PharmaceuticalSupplyChain(_pharmaSupplyChain);
        healthcareIdentityContract = HealthcareIdentity(_healthcareIdentity);
        clinicAppointmentsContract = ClinicAppointments(_clinicAppointments);

        systemConfig = SystemConfig({
            isMaintenanceMode: false,
            maxTransactionsPerBlock: 100,
            emergencyContactDelay: 24 hours,
            systemVersion: "1.0.0",
            emergencyContact: msg.sender
        });
    }

    /**
     * @dev Integrated workflow: Submit claim with medical record and process payment
     * @param _policyNumber Insurance policy number
     * @param _claimedAmount Amount being claimed
     * @param _diagnosis Medical diagnosis
     * @param _treatmentCode Treatment procedure code
     * @param _supportingDocuments IPFS hashes of supporting documents
     * @param _medicalRecordId Associated medical record ID
     * @param _isEmergencyClaim Whether this is an emergency claim
     */
    function submitClaimWithRecord(
        string memory _policyNumber,
        uint256 _claimedAmount,
        string memory _diagnosis,
        string memory _treatmentCode,
        string[] memory _supportingDocuments,
        uint256 _medicalRecordId,
        bool _isEmergencyClaim
    ) external notInMaintenanceMode {
        // Verify provider is authorized in identity contract
        require(
            healthcareIdentityContract.hasEntityRole(msg.sender, keccak256("PROVIDER_ROLE")),
            "Provider not verified in identity system"
        );

        // Submit claim to insurance contract
        insuranceClaimsContract.submitClaim(
            _policyNumber,
            _claimedAmount,
            _diagnosis,
            _treatmentCode,
            _supportingDocuments,
            _isEmergencyClaim,
            _medicalRecordId
        );

        // Get the claim ID (assumes it's the latest claim)
        uint256[] memory providerClaims = insuranceClaimsContract.getProviderClaims(msg.sender);
        uint256 claimId = providerClaims[providerClaims.length - 1];

        // Get claim details to check if auto-approved
        InsuranceClaims.Claim memory claim = insuranceClaimsContract.getClaim(claimId);
        
        emit ClaimSubmittedAndProcessed(
            claimId,
            claim.patient,
            msg.sender,
            _claimedAmount,
            claim.status == InsuranceClaims.ClaimStatus.Approved
        );

        emit MedicalRecordLinkedToClaim(_medicalRecordId, claimId, claim.patient);

        // If claim is auto-approved, process payment
        if (claim.status == InsuranceClaims.ClaimStatus.Approved) {
            _processClaimPayment(claimId, claim.approvedAmount, claim.insurer);
        }
    }

    /**
     * @dev Process payment for approved claim
     * @param _claimId Approved claim ID
     * @param _amount Amount to pay
     * @param _insurer Insurance company address
     */
    function _processClaimPayment(
        uint256 _claimId,
        uint256 _amount,
        address _insurer
    ) internal {
        InsuranceClaims.Claim memory claim = insuranceClaimsContract.getClaim(_claimId);
        
        // Execute payment through payment system
        paymentSystemContract.executeClaimPayout(
            _claimId,
            claim.provider,
            _amount,
            _insurer
        );

        // Mark claim as paid in insurance contract
        insuranceClaimsContract.markClaimAsPaid(_claimId);

        emit PaymentExecutedForClaim(_claimId, 0, claim.provider, _amount); // PaymentId would be returned from payment system
    }

    /**
     * @dev Integrated appointment and consultation workflow
     * @param _doctor Doctor address
     * @param _timeSlotId Available time slot ID
     * @param _symptoms Patient symptoms
     * @param _patientNotes Patient notes
     * @param _consultationType Type of consultation needed
     */
    function bookConsultationAndCreateRecord(
        address _doctor,
        uint256 _timeSlotId,
        string memory _symptoms,
        string memory _patientNotes,
        ClinicAppointments.ConsultationType _consultationType
    ) external notInMaintenanceMode {
        // Verify patient is registered
        require(
            healthcareIdentityContract.hasEntityRole(msg.sender, keccak256("PATIENT_ROLE")) ||
            patientRecordContract.hasRole(patientRecordContract.PATIENT_ROLE(), msg.sender),
            "Patient not verified"
        );

        // Book appointment
        string[] memory emptyAttachments;
        clinicAppointmentsContract.bookAppointment(
            _doctor,
            _timeSlotId,
            _consultationType,
            _symptoms,
            _patientNotes,
            emptyAttachments,
            false // not emergency
        );

        // Get the latest appointment ID for this patient
        uint256[] memory patientAppointments = clinicAppointmentsContract.getPatientAppointments(msg.sender);
        uint256 appointmentId = patientAppointments[patientAppointments.length - 1];

        emit AppointmentBookedWithRecord(appointmentId, msg.sender, _doctor, _symptoms);
    }

    /**
     * @dev Complete consultation and create medical record
     * @param _appointmentId Appointment ID
     * @param _diagnosis Diagnosis from consultation
     * @param _prescription Prescription details
     * @param _consultationNotes Doctor's notes
     */
    function completeConsultationWithRecord(
        uint256 _appointmentId,
        string memory _diagnosis,
        string memory _prescription,
        string memory _consultationNotes,
        string[] memory _attachments
    ) external notInMaintenanceMode {
        // Verify doctor authorization
        require(
            healthcareIdentityContract.hasEntityRole(msg.sender, keccak256("PROVIDER_ROLE")),
            "Doctor not verified"
        );

        // Get appointment details
        ClinicAppointments.Appointment memory appointment = clinicAppointmentsContract.getAppointment(_appointmentId);
        require(appointment.doctor == msg.sender, "Not your appointment");

        // Create medical record with consultation data
        string memory combinedData = string(abi.encodePacked(
            "Consultation: ", _diagnosis, " | Prescription: ", _prescription, " | Notes: ", _consultationNotes
        ));

        patientRecordContract.createMedicalRecord(
            appointment.patient,
            combinedData,
            "consultation",
            _attachments
        );

        // Complete consultation in appointment system
        string[] memory emptyTests;
        clinicAppointmentsContract.completeConsultation(
            _appointmentId, // This would need to be the consultation ID in practice
            _diagnosis,
            _prescription,
            emptyTests,
            "",
            _consultationNotes,
            ""
        );

        emit ConsultationCompletedWithRecord(_appointmentId, appointment.patient, msg.sender);
    }

    /**
     * @dev Emergency appointment booking
     * @param _doctor Doctor address
     * @param _symptoms Emergency symptoms
     * @param _patientNotes Patient notes
     */
    function bookEmergencyConsultation(
        address _doctor,
        string memory _symptoms,
        string memory _patientNotes
    ) external notInMaintenanceMode {
        // For emergency, we might need to create an immediate slot or use available one
        // This is a simplified implementation
        
        string[] memory emptyAttachments;
        clinicAppointmentsContract.bookAppointment(
            _doctor,
            0, // Emergency slot - would need special handling
            ClinicAppointments.ConsultationType.Emergency,
            _symptoms,
            _patientNotes,
            emptyAttachments,
            true // is emergency
        );

        emit EmergencyConsultationBooked(msg.sender, _doctor, _symptoms);
    }

    /**
     * @dev Emergency access workflow with audit trail
     * @param _patientAddress Patient address for emergency access
     * @param _recordId Medical record ID to access
     * @param _emergencyReason Reason for emergency access
     */
    function emergencyAccess(
        address _patientAddress,
        uint256 _recordId,
        string memory _emergencyReason
    ) external notInMaintenanceMode {
        // Verify emergency personnel
        require(
            healthcareIdentityContract.hasEntityRole(msg.sender, keccak256("PROVIDER_ROLE")) ||
            patientRecordContract.hasRole(patientRecordContract.EMERGENCY_ROLE(), msg.sender),
            "Not authorized for emergency access"
        );

        // Access medical record
        PatientRecord.MedicalRecord memory record = patientRecordContract.emergencyAccess(_recordId);
        
        // Additional audit logging could be added here
        // This demonstrates the integration between contracts for emergency scenarios
    }

    /**
     * @dev Get comprehensive patient health summary including appointments
     * @param _patientAddress Patient address
     */
    function getPatientHealthSummary(address _patientAddress) 
        external 
        view 
        notInMaintenanceMode
        returns (
            uint256[] memory recordIds,
            uint256[] memory claimIds,
            uint256[] memory appointmentIds,
            bool isVerifiedPatient,
            uint256 totalClaimsAmount,
            uint256 totalAppointments
        ) 
    {
        // Get medical records
        recordIds = patientRecordContract.getPatientRecords(_patientAddress);
        
        // Get insurance claims
        claimIds = insuranceClaimsContract.getPatientClaims(_patientAddress);
        
        // Get appointments
        appointmentIds = clinicAppointmentsContract.getPatientAppointments(_patientAddress);
        
        // Check if patient is verified in identity system
        (isVerifiedPatient,,) = healthcareIdentityContract.verifyEntity(_patientAddress);
        
        // Calculate total claims amount
        totalClaimsAmount = 0;
        for (uint256 i = 0; i < claimIds.length; i++) {
            InsuranceClaims.Claim memory claim = insuranceClaimsContract.getClaim(claimIds[i]);
            totalClaimsAmount += claim.approvedAmount;
        }

        totalAppointments = appointmentIds.length;
    }

    /**
     * @dev Verify provider credentials across all systems including clinic appointments
     * @param _providerAddress Provider address to verify
     */
    function verifyProviderCredentials(address _providerAddress) 
        external 
        view 
        returns (
            bool isVerifiedProvider,
            bool canAccessRecords,
            bool canSubmitClaims,
            bool canDispenseMedication,
            bool canManageAppointments
        ) 
    {
        // Check identity verification
        (isVerifiedProvider,,) = healthcareIdentityContract.verifyEntity(_providerAddress);
        
        // Check specific permissions
        canAccessRecords = patientRecordContract.hasRole(
            patientRecordContract.DOCTOR_ROLE(), 
            _providerAddress
        );
        
        canSubmitClaims = insuranceClaimsContract.hasRole(
            insuranceClaimsContract.PROVIDER_ROLE(),
            _providerAddress
        );
        
        canDispenseMedication = pharmaSupplyChainContract.hasRole(
            pharmaSupplyChainContract.PHARMACY_ROLE(),
            _providerAddress
        );

        canManageAppointments = clinicAppointmentsContract.hasRole(
            clinicAppointmentsContract.DOCTOR_ROLE(),
            _providerAddress
        );
    }

    /**
     * @dev Update system configuration
     * @param _parameter Parameter name to update
     * @param _value New value
     */
    function updateSystemConfig(string memory _parameter, string memory _value) 
        external 
        onlyRole(SYSTEM_ADMIN_ROLE) 
    {
        bytes32 paramHash = keccak256(bytes(_parameter));
        
        if (paramHash == keccak256(bytes("maintenance_mode"))) {
            systemConfig.isMaintenanceMode = keccak256(bytes(_value)) == keccak256(bytes("true"));
        } else if (paramHash == keccak256(bytes("system_version"))) {
            systemConfig.systemVersion = _value;
        } else if (paramHash == keccak256(bytes("max_transactions"))) {
            systemConfig.maxTransactionsPerBlock = stringToUint(_value);
        }
        
        emit SystemConfigUpdated(_parameter, _value);
    }

    /**
     * @dev Enable maintenance mode
     */
    function enableMaintenanceMode() external onlyRole(SYSTEM_ADMIN_ROLE) {
        systemConfig.isMaintenanceMode = true;
        emit SystemConfigUpdated("maintenance_mode", "true");
    }

    /**
     * @dev Disable maintenance mode
     */
    function disableMaintenanceMode() external onlyRole(SYSTEM_ADMIN_ROLE) {
        systemConfig.isMaintenanceMode = false;
        emit SystemConfigUpdated("maintenance_mode", "false");
    }

    /**
     * @dev Update contract addresses (for upgrades)
     * @param _contractName Name of contract to update
     * @param _newAddress New contract address
     */
    function updateContractAddress(
        string memory _contractName,
        address _newAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newAddress != address(0), "Invalid contract address");
        
        bytes32 nameHash = keccak256(bytes(_contractName));
        
        if (nameHash == keccak256(bytes("PatientRecord"))) {
            patientRecordContract = PatientRecord(_newAddress);
        } else if (nameHash == keccak256(bytes("InsuranceClaims"))) {
            insuranceClaimsContract = InsuranceClaims(_newAddress);
        } else if (nameHash == keccak256(bytes("PaymentSystem"))) {
            paymentSystemContract = PaymentSystem(_newAddress);
        } else if (nameHash == keccak256(bytes("PharmaceuticalSupplyChain"))) {
            pharmaSupplyChainContract = PharmaceuticalSupplyChain(_newAddress);
        } else if (nameHash == keccak256(bytes("HealthcareIdentity"))) {
            healthcareIdentityContract = HealthcareIdentity(_newAddress);
        } else if (nameHash == keccak256(bytes("ClinicAppointments"))) {
            clinicAppointmentsContract = ClinicAppointments(_newAddress);
        } else {
            revert("Unknown contract name");
        }
    }

    /**
     * @dev Get system health status
     */
    function getSystemHealth() 
        external 
        view 
        returns (
            bool isHealthy,
            bool maintenanceMode,
            string memory version,
            address[] memory contractAddresses
        ) 
    {
        contractAddresses = new address[](6);
        contractAddresses[0] = address(patientRecordContract);
        contractAddresses[1] = address(insuranceClaimsContract);
        contractAddresses[2] = address(paymentSystemContract);
        contractAddresses[3] = address(pharmaSupplyChainContract);
        contractAddresses[4] = address(healthcareIdentityContract);
        contractAddresses[5] = address(clinicAppointmentsContract);
        
        // Simple health check - all contracts should have non-zero addresses
        isHealthy = true;
        for (uint256 i = 0; i < contractAddresses.length; i++) {
            if (contractAddresses[i] == address(0)) {
                isHealthy = false;
                break;
            }
        }
        
        return (
            isHealthy,
            systemConfig.isMaintenanceMode,
            systemConfig.systemVersion,
            contractAddresses
        );
    }

    /**
     * @dev Helper function to convert string to uint
     */
    function stringToUint(string memory _str) internal pure returns (uint256) {
        bytes memory b = bytes(_str);
        uint256 result = 0;
        
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        
        return result;
    }

    /**
     * @dev Batch operation for system initialization
     * @param _patients Array of patient addresses to register
     * @param _providers Array of provider addresses to authorize
     */
    function batchInitialize(
        address[] memory _patients,
        address[] memory _providers
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // This would be used during system deployment to bootstrap the network
        // with initial verified entities
        
        for (uint256 i = 0; i < _patients.length; i++) {
            // Grant patient role across relevant contracts
            patientRecordContract.grantRole(patientRecordContract.PATIENT_ROLE(), _patients[i]);
            insuranceClaimsContract.grantRole(insuranceClaimsContract.PATIENT_ROLE(), _patients[i]);
        }
        
        for (uint256 i = 0; i < _providers.length; i++) {
            // Grant provider roles across relevant contracts
            patientRecordContract.grantRole(patientRecordContract.DOCTOR_ROLE(), _providers[i]);
            insuranceClaimsContract.grantRole(insuranceClaimsContract.PROVIDER_ROLE(), _providers[i]);
            pharmaSupplyChainContract.grantRole(pharmaSupplyChainContract.PHARMACY_ROLE(), _providers[i]);
        }
    }
}