// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title InsuranceClaims
 * @dev Smart contract for automated insurance claims processing in ChainCare ecosystem
 * Implements automated validation and settlement as described in the ChainCare documentation
 */
contract InsuranceClaims is AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;

    bytes32 public constant PATIENT_ROLE = keccak256("PATIENT_ROLE");
    bytes32 public constant PROVIDER_ROLE = keccak256("PROVIDER_ROLE");
    bytes32 public constant INSURER_ROLE = keccak256("INSURER_ROLE");
    bytes32 public constant CLAIMS_PROCESSOR_ROLE = keccak256("CLAIMS_PROCESSOR_ROLE");

    enum ClaimStatus {
        Submitted,
        UnderReview,
        Approved,
        Rejected,
        Paid,
        Disputed
    }

    struct Insurance {
        address policyHolder;
        string policyNumber;
        uint256 coverageAmount;
        uint256 deductible;
        uint256 remainingCoverage;
        bool isActive;
        uint256 expiryDate;
        string[] coveredConditions;
        address insurerAddress;
    }

    struct Claim {
        uint256 claimId;
        address patient;
        address provider;
        address insurer;
        string policyNumber;
        uint256 claimedAmount;
        uint256 approvedAmount;
        string diagnosis;
        string treatmentCode;
        string[] supportingDocuments; // IPFS hashes
        ClaimStatus status;
        uint256 submissionDate;
        uint256 reviewDate;
        uint256 settlementDate;
        string rejectionReason;
        bool isEmergencyClaim;
        uint256 medicalRecordId;
    }

    struct ClaimValidationRules {
        uint256 maxClaimAmount;
        uint256 minProviderExperience; // in months
        string[] requiredDocuments;
        uint256 autoApprovalThreshold;
        bool requiresManualReview;
    }

    Counters.Counter private claimIdCounter;
    
    mapping(string => Insurance) public insurancePolicies;
    mapping(uint256 => Claim) public claims;
    mapping(address => string[]) public patientPolicies;
    mapping(address => uint256[]) public patientClaims;
    mapping(address => uint256[]) public providerClaims;
    mapping(string => ClaimValidationRules) public validationRules;
    mapping(address => bool) public authorizedProviders;
    mapping(address => uint256) public providerExperienceMonths;

    event InsurancePolicyCreated(string indexed policyNumber, address indexed patient, address indexed insurer);
    event ClaimSubmitted(uint256 indexed claimId, address indexed patient, address indexed provider, uint256 amount);
    event ClaimApproved(uint256 indexed claimId, uint256 approvedAmount);
    event ClaimRejected(uint256 indexed claimId, string reason);
    event ClaimPaid(uint256 indexed claimId, uint256 amount, address recipient);
    event EmergencyClaimProcessed(uint256 indexed claimId, address indexed patient);
    event PolicyUpdated(string indexed policyNumber, uint256 remainingCoverage);

    modifier onlyPolicyHolder(string memory _policyNumber) {
        require(
            insurancePolicies[_policyNumber].policyHolder == msg.sender,
            "Only policy holder can perform this action"
        );
        _;
    }

    modifier validClaim(uint256 _claimId) {
        require(claims[_claimId].claimId != 0, "Claim does not exist");
        _;
    }

    modifier onlyAuthorizedForClaim(uint256 _claimId) {
        require(
            claims[_claimId].patient == msg.sender ||
            claims[_claimId].provider == msg.sender ||
            claims[_claimId].insurer == msg.sender ||
            hasRole(CLAIMS_PROCESSOR_ROLE, msg.sender),
            "Not authorized for this claim"
        );
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CLAIMS_PROCESSOR_ROLE, msg.sender);
    }

    /**
     * @dev Create a new insurance policy
     * @param _policyNumber Unique policy identifier
     * @param _policyHolder Address of the policy holder
     * @param _coverageAmount Total coverage amount
     * @param _deductible Policy deductible
     * @param _expiryDate Policy expiry timestamp
     * @param _coveredConditions Array of covered medical conditions
     */
    function createInsurancePolicy(
        string memory _policyNumber,
        address _policyHolder,
        uint256 _coverageAmount,
        uint256 _deductible,
        uint256 _expiryDate,
        string[] memory _coveredConditions
    ) external onlyRole(INSURER_ROLE) {
        require(bytes(_policyNumber).length > 0, "Policy number cannot be empty");
        require(_policyHolder != address(0), "Invalid policy holder address");
        require(insurancePolicies[_policyNumber].policyHolder == address(0), "Policy already exists");

        insurancePolicies[_policyNumber] = Insurance({
            policyHolder: _policyHolder,
            policyNumber: _policyNumber,
            coverageAmount: _coverageAmount,
            deductible: _deductible,
            remainingCoverage: _coverageAmount,
            isActive: true,
            expiryDate: _expiryDate,
            coveredConditions: _coveredConditions,
            insurerAddress: msg.sender
        });

        patientPolicies[_policyHolder].push(_policyNumber);
        _grantRole(PATIENT_ROLE, _policyHolder);

        emit InsurancePolicyCreated(_policyNumber, _policyHolder, msg.sender);
    }

    /**
     * @dev Submit an insurance claim
     * @param _policyNumber Policy number for the claim
     * @param _claimedAmount Amount being claimed
     * @param _diagnosis Medical diagnosis
     * @param _treatmentCode Treatment procedure code
     * @param _supportingDocuments IPFS hashes of supporting documents
     * @param _isEmergencyClaim Whether this is an emergency claim
     * @param _medicalRecordId Associated medical record ID
     */
    function submitClaim(
        string memory _policyNumber,
        uint256 _claimedAmount,
        string memory _diagnosis,
        string memory _treatmentCode,
        string[] memory _supportingDocuments,
        bool _isEmergencyClaim,
        uint256 _medicalRecordId
    ) external onlyRole(PROVIDER_ROLE) nonReentrant {
        require(authorizedProviders[msg.sender], "Provider not authorized");
        require(insurancePolicies[_policyNumber].isActive, "Policy not active");
        require(block.timestamp <= insurancePolicies[_policyNumber].expiryDate, "Policy expired");
        require(_claimedAmount > 0, "Claim amount must be greater than 0");

        claimIdCounter.increment();
        uint256 newClaimId = claimIdCounter.current();

        claims[newClaimId] = Claim({
            claimId: newClaimId,
            patient: insurancePolicies[_policyNumber].policyHolder,
            provider: msg.sender,
            insurer: insurancePolicies[_policyNumber].insurerAddress,
            policyNumber: _policyNumber,
            claimedAmount: _claimedAmount,
            approvedAmount: 0,
            diagnosis: _diagnosis,
            treatmentCode: _treatmentCode,
            supportingDocuments: _supportingDocuments,
            status: ClaimStatus.Submitted,
            submissionDate: block.timestamp,
            reviewDate: 0,
            settlementDate: 0,
            rejectionReason: "",
            isEmergencyClaim: _isEmergencyClaim,
            medicalRecordId: _medicalRecordId
        });

        patientClaims[insurancePolicies[_policyNumber].policyHolder].push(newClaimId);
        providerClaims[msg.sender].push(newClaimId);

        emit ClaimSubmitted(newClaimId, insurancePolicies[_policyNumber].policyHolder, msg.sender, _claimedAmount);

        // Auto-process if emergency claim or meets auto-approval criteria
        if (_isEmergencyClaim) {
            _processEmergencyClaim(newClaimId);
        } else {
            _evaluateForAutoApproval(newClaimId);
        }
    }

    /**
     * @dev Process emergency claim with expedited approval
     * @param _claimId ID of the emergency claim
     */
    function _processEmergencyClaim(uint256 _claimId) internal {
        Claim storage claim = claims[_claimId];
        Insurance storage policy = insurancePolicies[claim.policyNumber];

        // Emergency claims get 80% auto-approval up to remaining coverage
        uint256 emergencyApprovalAmount = (claim.claimedAmount * 80) / 100;
        if (emergencyApprovalAmount > policy.remainingCoverage) {
            emergencyApprovalAmount = policy.remainingCoverage;
        }

        claim.approvedAmount = emergencyApprovalAmount;
        claim.status = ClaimStatus.Approved;
        claim.reviewDate = block.timestamp;
        
        policy.remainingCoverage -= emergencyApprovalAmount;

        emit ClaimApproved(_claimId, emergencyApprovalAmount);
        emit EmergencyClaimProcessed(_claimId, claim.patient);
    }

    /**
     * @dev Evaluate claim for automatic approval based on predefined rules
     * @param _claimId ID of the claim to evaluate
     */
    function _evaluateForAutoApproval(uint256 _claimId) internal {
        Claim storage claim = claims[_claimId];
        ClaimValidationRules memory rules = validationRules[claim.treatmentCode];
        Insurance storage policy = insurancePolicies[claim.policyNumber];

        // Check if provider meets experience requirements
        if (providerExperienceMonths[claim.provider] < rules.minProviderExperience) {
            claim.status = ClaimStatus.UnderReview;
            return;
        }

        // Check if claim amount is within auto-approval threshold
        if (claim.claimedAmount <= rules.autoApprovalThreshold && 
            claim.claimedAmount <= policy.remainingCoverage) {
            
            claim.approvedAmount = claim.claimedAmount;
            claim.status = ClaimStatus.Approved;
            claim.reviewDate = block.timestamp;
            
            policy.remainingCoverage -= claim.claimedAmount;
            
            emit ClaimApproved(_claimId, claim.claimedAmount);
        } else {
            claim.status = ClaimStatus.UnderReview;
        }
    }

    /**
     * @dev Manually review and approve/reject a claim
     * @param _claimId ID of the claim
     * @param _approve Whether to approve or reject
     * @param _approvedAmount Amount approved (if approving)
     * @param _rejectionReason Reason for rejection (if rejecting)
     */
    function reviewClaim(
        uint256 _claimId,
        bool _approve,
        uint256 _approvedAmount,
        string memory _rejectionReason
    ) external validClaim(_claimId) {
        Claim storage claim = claims[_claimId];
        require(
            claim.insurer == msg.sender || hasRole(CLAIMS_PROCESSOR_ROLE, msg.sender),
            "Not authorized to review this claim"
        );
        require(
            claim.status == ClaimStatus.Submitted || claim.status == ClaimStatus.UnderReview,
            "Claim cannot be reviewed in current status"
        );

        claim.reviewDate = block.timestamp;

        if (_approve) {
            require(_approvedAmount > 0, "Approved amount must be greater than 0");
            require(
                _approvedAmount <= insurancePolicies[claim.policyNumber].remainingCoverage,
                "Insufficient remaining coverage"
            );

            claim.approvedAmount = _approvedAmount;
            claim.status = ClaimStatus.Approved;
            
            insurancePolicies[claim.policyNumber].remainingCoverage -= _approvedAmount;
            
            emit ClaimApproved(_claimId, _approvedAmount);
        } else {
            claim.status = ClaimStatus.Rejected;
            claim.rejectionReason = _rejectionReason;
            
            emit ClaimRejected(_claimId, _rejectionReason);
        }
    }

    /**
     * @dev Mark claim as paid (called by payment system)
     * @param _claimId ID of the claim
     */
    function markClaimAsPaid(uint256 _claimId) 
        external 
        validClaim(_claimId) 
        onlyRole(CLAIMS_PROCESSOR_ROLE) 
    {
        require(claims[_claimId].status == ClaimStatus.Approved, "Claim must be approved first");
        
        claims[_claimId].status = ClaimStatus.Paid;
        claims[_claimId].settlementDate = block.timestamp;
        
        emit ClaimPaid(_claimId, claims[_claimId].approvedAmount, claims[_claimId].provider);
    }

    /**
     * @dev Set validation rules for treatment codes
     * @param _treatmentCode Treatment code to set rules for
     * @param _rules Validation rules structure
     */
    function setValidationRules(
        string memory _treatmentCode,
        ClaimValidationRules memory _rules
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        validationRules[_treatmentCode] = _rules;
    }

    /**
     * @dev Authorize a healthcare provider
     * @param _provider Provider address
     * @param _experienceMonths Provider experience in months
     */
    function authorizeProvider(
        address _provider,
        uint256 _experienceMonths
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedProviders[_provider] = true;
        providerExperienceMonths[_provider] = _experienceMonths;
        _grantRole(PROVIDER_ROLE, _provider);
    }

    /**
     * @dev Get claim details
     * @param _claimId ID of the claim
     */
    function getClaim(uint256 _claimId) 
        external 
        view 
        validClaim(_claimId)
        onlyAuthorizedForClaim(_claimId)
        returns (Claim memory) 
    {
        return claims[_claimId];
    }

    /**
     * @dev Get patient's claims
     * @param _patient Patient address
     */
    function getPatientClaims(address _patient) 
        external 
        view 
        returns (uint256[] memory) 
    {
        require(
            msg.sender == _patient || hasRole(CLAIMS_PROCESSOR_ROLE, msg.sender),
            "Not authorized to view patient claims"
        );
        return patientClaims[_patient];
    }

    /**
     * @dev Get provider's claims
     * @param _provider Provider address
     */
    function getProviderClaims(address _provider) 
        external 
        view 
        returns (uint256[] memory) 
    {
        require(
            msg.sender == _provider || hasRole(CLAIMS_PROCESSOR_ROLE, msg.sender),
            "Not authorized to view provider claims"
        );
        return providerClaims[_provider];
    }

    /**
     * @dev Get insurance policy details
     * @param _policyNumber Policy number
     */
    function getInsurancePolicy(string memory _policyNumber) 
        external 
        view 
        returns (Insurance memory) 
    {
        require(
            insurancePolicies[_policyNumber].policyHolder == msg.sender ||
            insurancePolicies[_policyNumber].insurerAddress == msg.sender ||
            hasRole(CLAIMS_PROCESSOR_ROLE, msg.sender),
            "Not authorized to view this policy"
        );
        return insurancePolicies[_policyNumber];
    }

    /**
     * @dev Update policy coverage (for premium payments)
     * @param _policyNumber Policy number
     * @param _additionalCoverage Additional coverage to add
     */
    function updatePolicyCoverage(
        string memory _policyNumber,
        uint256 _additionalCoverage
    ) external {
        require(
            insurancePolicies[_policyNumber].insurerAddress == msg.sender,
            "Only insurer can update coverage"
        );
        
        insurancePolicies[_policyNumber].remainingCoverage += _additionalCoverage;
        insurancePolicies[_policyNumber].coverageAmount += _additionalCoverage;
        
        emit PolicyUpdated(_policyNumber, insurancePolicies[_policyNumber].remainingCoverage);
    }

    /**
     * @dev Dispute a claim
     * @param _claimId ID of the claim to dispute
     * @param _disputeReason Reason for the dispute
     */
    function disputeClaim(uint256 _claimId, string memory _disputeReason) 
        external 
        validClaim(_claimId) 
    {
        require(
            claims[_claimId].patient == msg.sender || claims[_claimId].provider == msg.sender,
            "Only patient or provider can dispute claim"
        );
        require(
            claims[_claimId].status == ClaimStatus.Rejected || 
            claims[_claimId].status == ClaimStatus.Approved,
            "Claim cannot be disputed in current status"
        );
        
        claims[_claimId].status = ClaimStatus.Disputed;
        claims[_claimId].rejectionReason = _disputeReason;
    }
}