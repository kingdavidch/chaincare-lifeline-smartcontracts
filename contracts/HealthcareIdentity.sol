// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title HealthcareIdentity
 * @dev Smart contract for managing healthcare provider and patient identities in ChainCare
 * Implements role-based access control and credential verification
 */
contract HealthcareIdentity is AccessControl, ReentrancyGuard {
    
    bytes32 public constant REGULATOR_ROLE = keccak256("REGULATOR_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant PATIENT_ROLE = keccak256("PATIENT_ROLE");
    bytes32 public constant PROVIDER_ROLE = keccak256("PROVIDER_ROLE");
    bytes32 public constant HOSPITAL_ROLE = keccak256("HOSPITAL_ROLE");
    bytes32 public constant PHARMACY_ROLE = keccak256("PHARMACY_ROLE");
    bytes32 public constant INSURER_ROLE = keccak256("INSURER_ROLE");

    enum CredentialStatus {
        Pending,
        Verified,
        Suspended,
        Revoked
    }

    enum EntityType {
        Patient,
        Doctor,
        Nurse,
        Hospital,
        Pharmacy,
        Laboratory,
        Insurer,
        Regulator
    }

    struct HealthcareEntity {
        address entityAddress;
        EntityType entityType;
        string name;
        string licenseNumber;
        string[] certifications;
        string jurisdiction;
        uint256 registrationDate;
        uint256 expiryDate;
        CredentialStatus status;
        address verifier;
        string contactInfo; // Encrypted contact information
        bool isActive;
        uint256 experienceYears;
        string specialization;
    }

    struct Credential {
        uint256 credentialId;
        address holder;
        string credentialType; // "medical_license", "specialty_cert", "hospital_accreditation"
        string issuingAuthority;
        string documentHash; // IPFS hash of credential document
        uint256 issueDate;
        uint256 expiryDate;
        CredentialStatus status;
        address verifier;
        bool isRevocable;
    }

    struct VerificationRequest {
        uint256 requestId;
        address applicant;
        EntityType requestedType;
        string[] submittedDocuments; // IPFS hashes
        uint256 requestDate;
        address assignedVerifier;
        bool isProcessed;
        bool isApproved;
        string verificationNotes;
    }

    mapping(address => HealthcareEntity) public entities;
    mapping(uint256 => Credential) public credentials;
    mapping(uint256 => VerificationRequest) public verificationRequests;
    mapping(address => uint256[]) public entityCredentials;
    mapping(address => bool) public registeredEntities;
    mapping(string => address) public licenseToAddress;
    mapping(address => uint256) public pendingRequests;
    
    uint256 private credentialIdCounter = 1;
    uint256 private requestIdCounter = 1;

    event EntityRegistered(address indexed entity, EntityType entityType, string name);
    event CredentialIssued(uint256 indexed credentialId, address indexed holder, string credentialType);
    event CredentialRevoked(uint256 indexed credentialId, address indexed revoker, string reason);
    event VerificationRequested(uint256 indexed requestId, address indexed applicant, EntityType entityType);
    event VerificationCompleted(uint256 indexed requestId, address indexed applicant, bool approved);
    event EntityStatusUpdated(address indexed entity, CredentialStatus newStatus);

    modifier onlyRegisteredEntity() {
        require(registeredEntities[msg.sender], "Entity not registered");
        _;
    }

    modifier onlyActiveEntity() {
        require(entities[msg.sender].isActive, "Entity not active");
        _;
    }

    modifier validCredential(uint256 _credentialId) {
        require(credentials[_credentialId].credentialId != 0, "Credential does not exist");
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGULATOR_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
    }

    /**
     * @dev Submit verification request for healthcare entity registration
     * @param _entityType Type of healthcare entity
     * @param _name Entity name
     * @param _licenseNumber Professional license number
     * @param _jurisdiction Operating jurisdiction
     * @param _submittedDocuments IPFS hashes of supporting documents
     * @param _contactInfo Encrypted contact information
     * @param _experienceYears Years of experience
     * @param _specialization Area of specialization
     */
    function requestVerification(
        EntityType _entityType,
        string memory _name,
        string memory _licenseNumber,
        string memory _jurisdiction,
        string[] memory _submittedDocuments,
        string memory _contactInfo,
        uint256 _experienceYears,
        string memory _specialization
    ) external {
        require(!registeredEntities[msg.sender], "Entity already registered");
        require(pendingRequests[msg.sender] == 0, "Verification request already pending");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_licenseNumber).length > 0, "License number cannot be empty");

        uint256 requestId = requestIdCounter++;
        
        verificationRequests[requestId] = VerificationRequest({
            requestId: requestId,
            applicant: msg.sender,
            requestedType: _entityType,
            submittedDocuments: _submittedDocuments,
            requestDate: block.timestamp,
            assignedVerifier: address(0),
            isProcessed: false,
            isApproved: false,
            verificationNotes: ""
        });

        pendingRequests[msg.sender] = requestId;

        // Temporarily store entity data for verification
        entities[msg.sender] = HealthcareEntity({
            entityAddress: msg.sender,
            entityType: _entityType,
            name: _name,
            licenseNumber: _licenseNumber,
            certifications: new string[](0),
            jurisdiction: _jurisdiction,
            registrationDate: block.timestamp,
            expiryDate: block.timestamp + 365 days, // Default 1 year
            status: CredentialStatus.Pending,
            verifier: address(0),
            contactInfo: _contactInfo,
            isActive: false,
            experienceYears: _experienceYears,
            specialization: _specialization
        });

        emit VerificationRequested(requestId, msg.sender, _entityType);
    }

    /**
     * @dev Assign verifier to verification request
     * @param _requestId Request ID
     * @param _verifier Verifier address
     */
    function assignVerifier(uint256 _requestId, address _verifier) 
        external 
        onlyRole(REGULATOR_ROLE) 
    {
        require(verificationRequests[_requestId].requestId != 0, "Request does not exist");
        require(!verificationRequests[_requestId].isProcessed, "Request already processed");
        require(hasRole(VERIFIER_ROLE, _verifier), "Address not authorized as verifier");

        verificationRequests[_requestId].assignedVerifier = _verifier;
    }

    /**
     * @dev Process verification request
     * @param _requestId Request ID
     * @param _approve Whether to approve the request
     * @param _verificationNotes Verification notes
     * @param _certifications Additional certifications to add
     */
    function processVerification(
        uint256 _requestId,
        bool _approve,
        string memory _verificationNotes,
        string[] memory _certifications
    ) external onlyRole(VERIFIER_ROLE) {
        VerificationRequest storage request = verificationRequests[_requestId];
        require(request.requestId != 0, "Request does not exist");
        require(!request.isProcessed, "Request already processed");
        require(
            request.assignedVerifier == msg.sender || hasRole(REGULATOR_ROLE, msg.sender),
            "Not assigned verifier"
        );

        request.isProcessed = true;
        request.isApproved = _approve;
        request.verificationNotes = _verificationNotes;

        HealthcareEntity storage entity = entities[request.applicant];
        
        if (_approve) {
            entity.status = CredentialStatus.Verified;
            entity.verifier = msg.sender;
            entity.isActive = true;
            entity.certifications = _certifications;
            
            registeredEntities[request.applicant] = true;
            licenseToAddress[entity.licenseNumber] = request.applicant;
            
            // Assign appropriate role based on entity type
            _assignEntityRole(request.applicant, entity.entityType);
            
            emit EntityRegistered(request.applicant, entity.entityType, entity.name);
        } else {
            entity.status = CredentialStatus.Revoked;
            delete entities[request.applicant];
        }

        delete pendingRequests[request.applicant];
        emit VerificationCompleted(_requestId, request.applicant, _approve);
    }

    /**
     * @dev Issue a credential to a healthcare entity
     * @param _holder Address of credential holder
     * @param _credentialType Type of credential
     * @param _issuingAuthority Issuing authority name
     * @param _documentHash IPFS hash of credential document
     * @param _expiryDate Credential expiry date
     * @param _isRevocable Whether credential can be revoked
     */
    function issueCredential(
        address _holder,
        string memory _credentialType,
        string memory _issuingAuthority,
        string memory _documentHash,
        uint256 _expiryDate,
        bool _isRevocable
    ) external onlyRole(VERIFIER_ROLE) {
        require(registeredEntities[_holder], "Holder not registered");
        require(_expiryDate > block.timestamp, "Expiry date must be in future");

        uint256 credentialId = credentialIdCounter++;
        
        credentials[credentialId] = Credential({
            credentialId: credentialId,
            holder: _holder,
            credentialType: _credentialType,
            issuingAuthority: _issuingAuthority,
            documentHash: _documentHash,
            issueDate: block.timestamp,
            expiryDate: _expiryDate,
            status: CredentialStatus.Verified,
            verifier: msg.sender,
            isRevocable: _isRevocable
        });

        entityCredentials[_holder].push(credentialId);
        
        emit CredentialIssued(credentialId, _holder, _credentialType);
    }

    /**
     * @dev Revoke a credential
     * @param _credentialId Credential ID to revoke
     * @param _reason Reason for revocation
     */
    function revokeCredential(uint256 _credentialId, string memory _reason) 
        external 
        onlyRole(VERIFIER_ROLE) 
        validCredential(_credentialId) 
    {
        Credential storage credential = credentials[_credentialId];
        require(credential.isRevocable, "Credential is not revocable");
        require(credential.status != CredentialStatus.Revoked, "Credential already revoked");

        credential.status = CredentialStatus.Revoked;
        
        emit CredentialRevoked(_credentialId, msg.sender, _reason);
    }

    /**
     * @dev Suspend an entity
     * @param _entity Entity address to suspend
     * @param _reason Reason for suspension
     */
    function suspendEntity(address _entity, string memory _reason) 
        external 
        onlyRole(REGULATOR_ROLE) 
    {
        require(registeredEntities[_entity], "Entity not registered");
        require(entities[_entity].isActive, "Entity already inactive");

        entities[_entity].status = CredentialStatus.Suspended;
        entities[_entity].isActive = false;
        
        emit EntityStatusUpdated(_entity, CredentialStatus.Suspended);
    }

    /**
     * @dev Reactivate a suspended entity
     * @param _entity Entity address to reactivate
     */
    function reactivateEntity(address _entity) 
        external 
        onlyRole(REGULATOR_ROLE) 
    {
        require(registeredEntities[_entity], "Entity not registered");
        require(entities[_entity].status == CredentialStatus.Suspended, "Entity not suspended");

        entities[_entity].status = CredentialStatus.Verified;
        entities[_entity].isActive = true;
        
        emit EntityStatusUpdated(_entity, CredentialStatus.Verified);
    }

    /**
     * @dev Update entity information
     * @param _contactInfo New encrypted contact information
     * @param _specialization New specialization
     */
    function updateEntityInfo(
        string memory _contactInfo,
        string memory _specialization
    ) external onlyRegisteredEntity {
        HealthcareEntity storage entity = entities[msg.sender];
        entity.contactInfo = _contactInfo;
        entity.specialization = _specialization;
    }

    /**
     * @dev Verify entity credentials
     * @param _entity Entity address to verify
     */
    function verifyEntity(address _entity) 
        external 
        view 
        returns (bool isValid, CredentialStatus status, uint256 expiryDate) 
    {
        if (!registeredEntities[_entity]) {
            return (false, CredentialStatus.Revoked, 0);
        }
        
        HealthcareEntity memory entity = entities[_entity];
        bool isExpired = entity.expiryDate <= block.timestamp;
        
        return (
            !isExpired && entity.isActive && entity.status == CredentialStatus.Verified,
            entity.status,
            entity.expiryDate
        );
    }

    /**
     * @dev Get entity details
     * @param _entity Entity address
     */
    function getEntity(address _entity) 
        external 
        view 
        returns (HealthcareEntity memory) 
    {
        require(registeredEntities[_entity], "Entity not registered");
        return entities[_entity];
    }

    /**
     * @dev Get entity by license number
     * @param _licenseNumber License number
     */
    function getEntityByLicense(string memory _licenseNumber) 
        external 
        view 
        returns (HealthcareEntity memory) 
    {
        address entityAddress = licenseToAddress[_licenseNumber];
        require(entityAddress != address(0), "License not found");
        return entities[entityAddress];
    }

    /**
     * @dev Get entity credentials
     * @param _entity Entity address
     */
    function getEntityCredentials(address _entity) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return entityCredentials[_entity];
    }

    /**
     * @dev Get credential details
     * @param _credentialId Credential ID
     */
    function getCredential(uint256 _credentialId) 
        external 
        view 
        validCredential(_credentialId)
        returns (Credential memory) 
    {
        return credentials[_credentialId];
    }

    /**
     * @dev Get verification request details
     * @param _requestId Request ID
     */
    function getVerificationRequest(uint256 _requestId) 
        external 
        view 
        returns (VerificationRequest memory) 
    {
        require(verificationRequests[_requestId].requestId != 0, "Request does not exist");
        return verificationRequests[_requestId];
    }

    /**
     * @dev Check if entity has specific role
     * @param _entity Entity address
     * @param _role Role to check
     */
    function hasEntityRole(address _entity, bytes32 _role) 
        external 
        view 
        returns (bool) 
    {
        return hasRole(_role, _entity);
    }

    /**
     * @dev Assign role based on entity type
     */
    function _assignEntityRole(address _entity, EntityType _entityType) internal {
        if (_entityType == EntityType.Patient) {
            _grantRole(PATIENT_ROLE, _entity);
        } else if (_entityType == EntityType.Doctor || _entityType == EntityType.Nurse) {
            _grantRole(PROVIDER_ROLE, _entity);
        } else if (_entityType == EntityType.Hospital) {
            _grantRole(HOSPITAL_ROLE, _entity);
        } else if (_entityType == EntityType.Pharmacy) {
            _grantRole(PHARMACY_ROLE, _entity);
        } else if (_entityType == EntityType.Insurer) {
            _grantRole(INSURER_ROLE, _entity);
        } else if (_entityType == EntityType.Regulator) {
            _grantRole(REGULATOR_ROLE, _entity);
        }
    }

    /**
     * @dev Extend entity registration
     * @param _entity Entity address
     * @param _additionalDays Days to extend registration
     */
    function extendRegistration(address _entity, uint256 _additionalDays) 
        external 
        onlyRole(REGULATOR_ROLE) 
    {
        require(registeredEntities[_entity], "Entity not registered");
        entities[_entity].expiryDate += _additionalDays * 1 days;
    }

    /**
     * @dev Bulk verify entities (for migration or batch processing)
     * @param _entities Array of entity addresses
     * @param _entityTypes Array of entity types
     * @param _names Array of entity names
     * @param _licenseNumbers Array of license numbers
     */
    function bulkVerifyEntities(
        address[] memory _entities,
        EntityType[] memory _entityTypes,
        string[] memory _names,
        string[] memory _licenseNumbers
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _entities.length == _entityTypes.length &&
            _entities.length == _names.length &&
            _entities.length == _licenseNumbers.length,
            "Array lengths must match"
        );

        for (uint256 i = 0; i < _entities.length; i++) {
            if (!registeredEntities[_entities[i]]) {
                entities[_entities[i]] = HealthcareEntity({
                    entityAddress: _entities[i],
                    entityType: _entityTypes[i],
                    name: _names[i],
                    licenseNumber: _licenseNumbers[i],
                    certifications: new string[](0),
                    jurisdiction: "Bulk Import",
                    registrationDate: block.timestamp,
                    expiryDate: block.timestamp + 365 days,
                    status: CredentialStatus.Verified,
                    verifier: msg.sender,
                    contactInfo: "",
                    isActive: true,
                    experienceYears: 0,
                    specialization: ""
                });

                registeredEntities[_entities[i]] = true;
                licenseToAddress[_licenseNumbers[i]] = _entities[i];
                _assignEntityRole(_entities[i], _entityTypes[i]);
                
                emit EntityRegistered(_entities[i], _entityTypes[i], _names[i]);
            }
        }
    }
}