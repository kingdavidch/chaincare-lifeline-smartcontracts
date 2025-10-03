# ChainCare Smart Contracts

## 🎥 **DEMO VIDEO**
### **[Watch the ChainCare Demo Video →](https://youtu.be/qqwbecFv3vw)**
*See the complete ChainCare blockchain healthcare ecosystem in action!*

---

This repository contains the complete set of smart contracts for the ChainCare blockchain-powered healthcare ecosystem, designed based on the requirements outlined in the ChainCare documentation.

## Overview

ChainCare is a comprehensive blockchain solution that addresses three core healthcare challenges:
1. **Secure clinical and pharmaceutical data management**
2. **Automated insurance claims processing** 
3. **Efficient stablecoin-based payments**

## Smart Contracts

### 1. PatientRecord.sol
**Purpose**: Secure management of patient medical records with privacy controls

**Key Features**:
- Patient registration and consent management
- Encrypted medical record storage (IPFS integration)
- Role-based access control (patients, doctors, hospitals, emergency personnel)
- Audit logging for all data access
- Emergency access capabilities
- Medical record deactivation

**Main Functions**:
- `registerPatient()` - Register new patient
- `createMedicalRecord()` - Create encrypted medical record
- `grantAccess()` / `revokeAccess()` - Manage data access permissions
- `emergencyAccess()` - Emergency medical record access
- `getMedicalRecord()` - Retrieve medical records (authorized access only)

### 2. InsuranceClaims.sol
**Purpose**: Automated insurance claims processing and validation

**Key Features**:
- Insurance policy management
- Automated claims validation based on predefined rules
- Emergency claim processing (80% auto-approval)
- Provider authorization and experience tracking
- Claims dispute resolution
- Integration with payment system

**Main Functions**:
- `createInsurancePolicy()` - Set up insurance policies
- `submitClaim()` - Submit insurance claims
- `reviewClaim()` - Manual claim review for complex cases
- `markClaimAsPaid()` - Update claim status after payment
- `disputeClaim()` - Handle claim disputes

### 3. PaymentSystem.sol
**Purpose**: Stablecoin-based payment processing for healthcare transactions

**Key Features**:
- Multi-stablecoin support (USDC, USDT, DAI)
- Automated claim payouts
- Escrow payment functionality
- Platform fee management
- Transaction audit trail
- Emergency pause functionality

**Main Functions**:
- `processPayment()` - Process general payments
- `executeClaimPayout()` - Execute insurance claim payments
- `createEscrow()` / `releaseEscrow()` - Escrow payment management
- `addStablecoin()` - Add supported stablecoins

### 4. PharmaceuticalSupplyChain.sol
**Purpose**: End-to-end pharmaceutical supply chain tracking and counterfeit prevention

**Key Features**:
- Complete drug traceability from manufacture to dispensing
- Quality check recording and certification
- Product recall management
- Counterfeit detection and reporting
- Multi-stakeholder transaction logging
- Storage condition monitoring

**Main Functions**:
- `manufactureProduct()` - Record pharmaceutical manufacturing
- `shipProduct()` - Track product shipments
- `confirmDelivery()` - Confirm product delivery
- `dispenseProduct()` - Record medication dispensing
- `performQualityCheck()` - Quality assurance checks
- `initiateRecall()` - Product recall management

### 5. HealthcareIdentity.sol
**Purpose**: Healthcare provider and patient identity verification and credential management

**Key Features**:
- Multi-entity type support (patients, doctors, hospitals, pharmacies, insurers)
- Credential verification workflow
- Professional license validation
- Role-based access assignment
- Credential revocation and suspension
- Bulk entity verification for system initialization

**Main Functions**:
- `requestVerification()` - Submit verification request
- `processVerification()` - Verify entity credentials
- `issueCredential()` - Issue professional credentials
- `verifyEntity()` - Check entity verification status
- `suspendEntity()` / `reactivateEntity()` - Entity status management

### 6. ClinicAppointments.sol
**Purpose**: Comprehensive clinic appointment booking and consultation management system

**Key Features**:
- Clinic registration and management
- Doctor registration with specializations and availability
- Time slot creation and management
- Appointment booking with different consultation types
- Patient queue management and check-in system
- Consultation workflow from booking to completion
- Emergency appointment handling
- Doctor rating and feedback system
- Appointment cancellation and rescheduling

**Main Functions**:
- `registerClinic()` - Register healthcare clinics
- `registerDoctor()` - Register doctors to clinics
- `createTimeSlots()` - Create available appointment slots
- `bookAppointment()` - Book patient appointments
- `startConsultation()` / `completeConsultation()` - Consultation workflow
- `cancelAppointment()` - Cancel or reschedule appointments
- `checkInPatient()` - Patient check-in and queue management

### 7. ChainCareHub.sol
**Purpose**: Main orchestration contract coordinating all system components

**Key Features**:
- Integrated workflows across all contracts
- System health monitoring
- Maintenance mode management
- Cross-contract verification
- Batch operations for system initialization
- Emergency access coordination

**Main Functions**:
- `submitClaimWithRecord()` - Integrated claim submission with medical records
- `bookConsultationAndCreateRecord()` - Integrated appointment booking with record creation
- `completeConsultationWithRecord()` - Complete consultation and create medical records
- `bookEmergencyConsultation()` - Emergency appointment booking
- `prescribeAndDispense()` - Prescription workflow management
- `emergencyAccess()` - Emergency access across all systems
- `getPatientHealthSummary()` - Comprehensive patient data aggregation including appointments
- `verifyProviderCredentials()` - Cross-system provider verification

## Technical Architecture

### Security Features
- **Multi-layer access control** using OpenZeppelin's AccessControl
- **Reentrancy protection** for all financial transactions
- **Input validation** and bounds checking
- **Emergency pause mechanisms** for critical operations
- **Audit trails** for all sensitive operations

### Privacy Implementation
- **Encrypted data storage** with IPFS hash references
- **Private data collections** architecture (as per Hyperledger Fabric requirements)
- **Granular access controls** with patient consent management
- **Role-based permissions** across all stakeholder types

### Integration Points
- **IPFS** for encrypted document storage
- **Stablecoin protocols** (USDC, USDT, DAI) for payments
- **Oracle integration** capabilities for external data verification
- **Event logging** for off-chain monitoring and analytics

## Deployment Architecture

The contracts are designed for deployment on a **Hyperledger Fabric permissioned network** as specified in the ChainCare documentation, with the following participants:

- **Peer 0**: Hospital
- **Peer 1**: Pharmacy
- **Peer 2**: Insurer
- **Peer 3**: Laboratory

### Network Configuration
- **Consensus**: Practical Byzantine Fault Tolerance (PBFT)
- **Throughput**: 550 TPS capacity
- **Block Time**: 2-3 seconds
- **Security**: TLS 1.3 encryption, AES-256 data encryption

## Usage Examples

### Patient Registration and Medical Record Creation
```solidity
// 1. Register patient
patientRecord.registerPatient(encryptedPersonalInfo, emergencyContact);

// 2. Grant access to doctor
patientRecord.grantAccess(doctorAddress, "doctor");

// 3. Doctor creates medical record
patientRecord.createMedicalRecord(patientAddress, encryptedData, "diagnosis", attachments);
```

### Insurance Claim Processing
```solidity
// 1. Create insurance policy
insuranceClaims.createInsurancePolicy(policyNumber, patientAddress, coverageAmount, deductible, expiryDate, conditions);

// 2. Provider submits claim
insuranceClaims.submitClaim(policyNumber, claimedAmount, diagnosis, treatmentCode, documents, false, recordId);

// 3. Automatic payment processing (if auto-approved)
paymentSystem.executeClaimPayout(claimId, providerAddress, amount, insurerAddress);
```

### Clinic Appointment Booking and Consultation
```solidity
// 1. Register clinic
clinicAppointments.registerClinic("City Health Clinic", "Downtown", services, contactInfo, "08:00-17:00", operatingDays, consultationFee, true);

// 2. Register doctor to clinic
clinicAppointments.registerDoctor(doctorAddress, clinicId, "Dr. Smith", "General Medicine", licenseNumber, fee, availableDays, timeSlots, 10, qualifications);

// 3. Create time slots
string[] memory times = ["09:00", "10:00", "11:00"];
clinicAppointments.createTimeSlots(doctorAddress, "2025-10-15", times, 30, consultationFee);

// 4. Book appointment
clinicAppointments.bookAppointment(doctorAddress, timeSlotId, ConsultationType.GeneralConsultation, symptoms, patientNotes, attachments, false);

// 5. Complete consultation
clinicAppointments.completeConsultation(consultationId, diagnosis, prescription, tests, nextAppointment, consultationNotes, followUpInstructions);
```

## Development and Testing

### Prerequisites
- Solidity ^0.8.19
- OpenZeppelin Contracts
- Hardhat or Truffle for testing
- Node.js and npm

### Installation
```bash
npm install @openzeppelin/contracts
npm install --save-dev hardhat
```

### Testing
The contracts include comprehensive test coverage for:
- Access control mechanisms
- Business logic validation
- Emergency scenarios
- Integration workflows
- Security edge cases

## Compliance and Regulatory Considerations

The smart contracts are designed with the following compliance frameworks in mind:
- **HIPAA** compliance for patient data protection
- **GDPR** right to be forgotten (via record deactivation)
- **FDA** pharmaceutical tracking requirements
- **Insurance regulatory** frameworks for claims processing

## Performance Metrics

Based on the ChainCare documentation specifications:
- **Transaction Time**: 3-5 seconds average
- **Throughput**: 550 TPS on Hyperledger Fabric
- **Consensus Finality**: Immediate (no probabilistic finality)
- **Gas Optimization**: Efficient state management and batch operations

## Future Enhancements

Planned improvements include:
- **AI-powered fraud detection** integration
- **Cross-border payment** optimization
- **IoT device integration** for real-time health monitoring
- **Interoperability** with existing healthcare systems
- **Advanced analytics** and reporting capabilities

## License

MIT License - See LICENSE file for details

## Support and Documentation

For technical support and detailed API documentation, please refer to:
- Smart contract documentation (auto-generated)
- Integration guides
- API reference materials
- Best practices documentation

---

**Note**: These smart contracts implement the complete ChainCare ecosystem as described in the project documentation, providing a secure, scalable, and interoperable blockchain solution for healthcare data management, insurance claims processing, and payment systems in low-resource settings.