// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title PharmaceuticalSupplyChain
 * @dev Smart contract for pharmaceutical supply chain management in ChainCare ecosystem
 * Provides end-to-end traceability and counterfeit prevention as mentioned in the documentation
 */
contract PharmaceuticalSupplyChain is AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;

    bytes32 public constant MANUFACTURER_ROLE = keccak256("MANUFACTURER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant PHARMACY_ROLE = keccak256("PHARMACY_ROLE");
    bytes32 public constant REGULATOR_ROLE = keccak256("REGULATOR_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    enum ProductStatus {
        Manufactured,
        InTransit,
        Delivered,
        Dispensed,
        Recalled,
        Expired
    }

    enum TransactionType {
        Manufacturing,
        Shipment,
        Delivery,
        Dispensing,
        Recall,
        QualityCheck
    }

    struct Pharmaceutical {
        uint256 productId;
        string batchNumber;
        string drugName;
        string activeIngredient;
        uint256 quantity;
        uint256 manufactureDate;
        uint256 expiryDate;
        address manufacturer;
        string manufacturingLocation;
        ProductStatus status;
        bool isRecalled;
        string[] certifications; // FDA, WHO, etc.
        uint256 unitPrice;
        string storageConditions;
        uint256[] transactionHistory;
    }

    struct SupplyChainTransaction {
        uint256 transactionId;
        uint256 productId;
        address from;
        address to;
        uint256 quantity;
        uint256 timestamp;
        TransactionType transactionType;
        string location;
        string conditions; // Temperature, humidity during transport
        string digitalSignature;
        bool isVerified;
        string notes;
    }

    struct QualityCheck {
        uint256 checkId;
        uint256 productId;
        address inspector;
        uint256 timestamp;
        bool passed;
        string testResults;
        string certificateHash; // IPFS hash of quality certificate
        uint256 temperature;
        uint256 humidity;
    }

    struct Recall {
        uint256 recallId;
        uint256 productId;
        address initiator;
        uint256 timestamp;
        string reason;
        uint256 affectedQuantity;
        bool isActive;
        address[] notifiedStakeholders;
    }

    Counters.Counter private productIdCounter;
    Counters.Counter private transactionIdCounter;
    Counters.Counter private qualityCheckIdCounter;
    Counters.Counter private recallIdCounter;

    mapping(uint256 => Pharmaceutical) public pharmaceuticals;
    mapping(uint256 => SupplyChainTransaction) public transactions;
    mapping(uint256 => QualityCheck) public qualityChecks;
    mapping(uint256 => Recall) public recalls;
    mapping(string => uint256) public batchToProductId;
    mapping(address => bool) public authorizedEntities;
    mapping(uint256 => uint256[]) public productQualityChecks;
    mapping(uint256 => uint256[]) public productRecalls;
    mapping(address => uint256[]) public entityProducts;

    event ProductManufactured(
        uint256 indexed productId,
        string batchNumber,
        address indexed manufacturer,
        uint256 quantity
    );
    event ProductShipped(
        uint256 indexed productId,
        address indexed from,
        address indexed to,
        uint256 quantity
    );
    event ProductDelivered(
        uint256 indexed productId,
        address indexed to,
        uint256 quantity
    );
    event ProductDispensed(
        uint256 indexed productId,
        address indexed pharmacy,
        uint256 quantity,
        address patient
    );
    event QualityCheckPerformed(
        uint256 indexed checkId,
        uint256 indexed productId,
        bool passed,
        address inspector
    );
    event ProductRecalled(
        uint256 indexed recallId,
        uint256 indexed productId,
        string reason,
        address initiator
    );
    event CounterfeitDetected(
        uint256 indexed productId,
        address reporter,
        string evidence
    );

    modifier onlyAuthorizedEntity() {
        require(authorizedEntities[msg.sender], "Not authorized entity");
        _;
    }

    modifier validProduct(uint256 _productId) {
        require(pharmaceuticals[_productId].productId != 0, "Product does not exist");
        _;
    }

    modifier notRecalled(uint256 _productId) {
        require(!pharmaceuticals[_productId].isRecalled, "Product is recalled");
        _;
    }

    modifier notExpired(uint256 _productId) {
        require(
            pharmaceuticals[_productId].expiryDate > block.timestamp,
            "Product has expired"
        );
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGULATOR_ROLE, msg.sender);
        
        productIdCounter.increment(); // Start from 1
        transactionIdCounter.increment();
        qualityCheckIdCounter.increment();
        recallIdCounter.increment();
    }

    /**
     * @dev Manufacture a new pharmaceutical product
     * @param _batchNumber Unique batch identifier
     * @param _drugName Name of the drug
     * @param _activeIngredient Active pharmaceutical ingredient
     * @param _quantity Total quantity manufactured
     * @param _expiryDate Product expiry timestamp
     * @param _manufacturingLocation Location of manufacturing
     * @param _certifications Quality certifications
     * @param _unitPrice Price per unit
     * @param _storageConditions Required storage conditions
     */
    function manufactureProduct(
        string memory _batchNumber,
        string memory _drugName,
        string memory _activeIngredient,
        uint256 _quantity,
        uint256 _expiryDate,
        string memory _manufacturingLocation,
        string[] memory _certifications,
        uint256 _unitPrice,
        string memory _storageConditions
    ) external onlyRole(MANUFACTURER_ROLE) {
        require(bytes(_batchNumber).length > 0, "Batch number cannot be empty");
        require(batchToProductId[_batchNumber] == 0, "Batch number already exists");
        require(_quantity > 0, "Quantity must be greater than 0");
        require(_expiryDate > block.timestamp, "Expiry date must be in future");

        uint256 productId = productIdCounter.current();
        productIdCounter.increment();

        uint256[] memory emptyArray;
        
        pharmaceuticals[productId] = Pharmaceutical({
            productId: productId,
            batchNumber: _batchNumber,
            drugName: _drugName,
            activeIngredient: _activeIngredient,
            quantity: _quantity,
            manufactureDate: block.timestamp,
            expiryDate: _expiryDate,
            manufacturer: msg.sender,
            manufacturingLocation: _manufacturingLocation,
            status: ProductStatus.Manufactured,
            isRecalled: false,
            certifications: _certifications,
            unitPrice: _unitPrice,
            storageConditions: _storageConditions,
            transactionHistory: emptyArray
        });

        batchToProductId[_batchNumber] = productId;
        entityProducts[msg.sender].push(productId);

        // Record manufacturing transaction
        _recordTransaction(
            productId,
            address(0),
            msg.sender,
            _quantity,
            TransactionType.Manufacturing,
            _manufacturingLocation,
            _storageConditions,
            ""
        );

        emit ProductManufactured(productId, _batchNumber, msg.sender, _quantity);
    }

    /**
     * @dev Ship product to another entity
     * @param _productId Product to ship
     * @param _to Recipient address
     * @param _quantity Quantity to ship
     * @param _location Current location
     * @param _conditions Transport conditions
     * @param _digitalSignature Digital signature for verification
     */
    function shipProduct(
        uint256 _productId,
        address _to,
        uint256 _quantity,
        string memory _location,
        string memory _conditions,
        string memory _digitalSignature
    ) external validProduct(_productId) notRecalled(_productId) notExpired(_productId) {
        Pharmaceutical storage product = pharmaceuticals[_productId];
        
        require(
            hasRole(MANUFACTURER_ROLE, msg.sender) ||
            hasRole(DISTRIBUTOR_ROLE, msg.sender),
            "Not authorized to ship"
        );
        require(authorizedEntities[_to], "Recipient not authorized");
        require(product.quantity >= _quantity, "Insufficient quantity");

        // Update product status and quantity
        product.quantity -= _quantity;
        if (product.status == ProductStatus.Manufactured) {
            product.status = ProductStatus.InTransit;
        }

        // Record shipment transaction
        _recordTransaction(
            _productId,
            msg.sender,
            _to,
            _quantity,
            TransactionType.Shipment,
            _location,
            _conditions,
            _digitalSignature
        );

        emit ProductShipped(_productId, msg.sender, _to, _quantity);
    }

    /**
     * @dev Confirm delivery of product
     * @param _productId Product ID
     * @param _quantity Quantity received
     * @param _location Delivery location
     * @param _conditions Conditions upon delivery
     */
    function confirmDelivery(
        uint256 _productId,
        uint256 _quantity,
        string memory _location,
        string memory _conditions
    ) external validProduct(_productId) notRecalled(_productId) {
        require(authorizedEntities[msg.sender], "Not authorized entity");

        Pharmaceutical storage product = pharmaceuticals[_productId];
        product.status = ProductStatus.Delivered;

        // Record delivery transaction
        _recordTransaction(
            _productId,
            address(0), // From address unknown in delivery confirmation
            msg.sender,
            _quantity,
            TransactionType.Delivery,
            _location,
            _conditions,
            ""
        );

        emit ProductDelivered(_productId, msg.sender, _quantity);
    }

    /**
     * @dev Dispense product to patient
     * @param _productId Product to dispense
     * @param _quantity Quantity dispensed
     * @param _patient Patient address
     * @param _prescription Prescription hash or ID
     */
    function dispenseProduct(
        uint256 _productId,
        uint256 _quantity,
        address _patient,
        string memory _prescription
    ) external 
        onlyRole(PHARMACY_ROLE) 
        validProduct(_productId) 
        notRecalled(_productId) 
        notExpired(_productId) 
    {
        Pharmaceutical storage product = pharmaceuticals[_productId];
        require(product.quantity >= _quantity, "Insufficient quantity available");

        product.quantity -= _quantity;
        product.status = ProductStatus.Dispensed;

        // Record dispensing transaction
        _recordTransaction(
            _productId,
            msg.sender,
            _patient,
            _quantity,
            TransactionType.Dispensing,
            "", // Location not critical for dispensing
            _prescription,
            ""
        );

        emit ProductDispensed(_productId, msg.sender, _quantity, _patient);
    }

    /**
     * @dev Perform quality check on product
     * @param _productId Product to check
     * @param _passed Whether product passed quality check
     * @param _testResults Test results description
     * @param _certificateHash IPFS hash of certificate
     * @param _temperature Storage temperature
     * @param _humidity Storage humidity
     */
    function performQualityCheck(
        uint256 _productId,
        bool _passed,
        string memory _testResults,
        string memory _certificateHash,
        uint256 _temperature,
        uint256 _humidity
    ) external onlyRole(AUDITOR_ROLE) validProduct(_productId) {
        uint256 checkId = qualityCheckIdCounter.current();
        qualityCheckIdCounter.increment();

        qualityChecks[checkId] = QualityCheck({
            checkId: checkId,
            productId: _productId,
            inspector: msg.sender,
            timestamp: block.timestamp,
            passed: _passed,
            testResults: _testResults,
            certificateHash: _certificateHash,
            temperature: _temperature,
            humidity: _humidity
        });

        productQualityChecks[_productId].push(checkId);

        // Record quality check transaction
        _recordTransaction(
            _productId,
            msg.sender,
            msg.sender,
            0, // No quantity change
            TransactionType.QualityCheck,
            "",
            _testResults,
            ""
        );

        emit QualityCheckPerformed(checkId, _productId, _passed, msg.sender);
    }

    /**
     * @dev Initiate product recall
     * @param _productId Product to recall
     * @param _reason Reason for recall
     * @param _affectedQuantity Quantity affected by recall
     * @param _stakeholders Addresses to notify
     */
    function initiateRecall(
        uint256 _productId,
        string memory _reason,
        uint256 _affectedQuantity,
        address[] memory _stakeholders
    ) external validProduct(_productId) {
        require(
            hasRole(MANUFACTURER_ROLE, msg.sender) ||
            hasRole(REGULATOR_ROLE, msg.sender),
            "Not authorized to initiate recall"
        );

        uint256 recallId = recallIdCounter.current();
        recallIdCounter.increment();

        recalls[recallId] = Recall({
            recallId: recallId,
            productId: _productId,
            initiator: msg.sender,
            timestamp: block.timestamp,
            reason: _reason,
            affectedQuantity: _affectedQuantity,
            isActive: true,
            notifiedStakeholders: _stakeholders
        });

        pharmaceuticals[_productId].isRecalled = true;
        pharmaceuticals[_productId].status = ProductStatus.Recalled;
        productRecalls[_productId].push(recallId);

        // Record recall transaction
        _recordTransaction(
            _productId,
            msg.sender,
            address(0),
            _affectedQuantity,
            TransactionType.Recall,
            "",
            _reason,
            ""
        );

        emit ProductRecalled(recallId, _productId, _reason, msg.sender);
    }

    /**
     * @dev Report counterfeit product
     * @param _productId Suspected counterfeit product
     * @param _evidence Evidence of counterfeiting
     */
    function reportCounterfeit(
        uint256 _productId,
        string memory _evidence
    ) external validProduct(_productId) {
        // Mark product as potentially counterfeit for investigation
        pharmaceuticals[_productId].status = ProductStatus.Recalled;
        
        emit CounterfeitDetected(_productId, msg.sender, _evidence);
    }

    /**
     * @dev Record a supply chain transaction
     */
    function _recordTransaction(
        uint256 _productId,
        address _from,
        address _to,
        uint256 _quantity,
        TransactionType _type,
        string memory _location,
        string memory _conditions,
        string memory _digitalSignature
    ) internal {
        uint256 transactionId = transactionIdCounter.current();
        transactionIdCounter.increment();

        transactions[transactionId] = SupplyChainTransaction({
            transactionId: transactionId,
            productId: _productId,
            from: _from,
            to: _to,
            quantity: _quantity,
            timestamp: block.timestamp,
            transactionType: _type,
            location: _location,
            conditions: _conditions,
            digitalSignature: _digitalSignature,
            isVerified: true, // Auto-verify on-chain transactions
            notes: ""
        });

        pharmaceuticals[_productId].transactionHistory.push(transactionId);
    }

    /**
     * @dev Authorize an entity to participate in supply chain
     * @param _entity Entity address
     * @param _role Role to assign
     */
    function authorizeEntity(address _entity, bytes32 _role) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        authorizedEntities[_entity] = true;
        _grantRole(_role, _entity);
    }

    /**
     * @dev Get product details
     * @param _productId Product ID
     */
    function getProduct(uint256 _productId) 
        external 
        view 
        validProduct(_productId)
        returns (Pharmaceutical memory) 
    {
        return pharmaceuticals[_productId];
    }

    /**
     * @dev Get product by batch number
     * @param _batchNumber Batch number
     */
    function getProductByBatch(string memory _batchNumber) 
        external 
        view 
        returns (Pharmaceutical memory) 
    {
        uint256 productId = batchToProductId[_batchNumber];
        require(productId != 0, "Batch number not found");
        return pharmaceuticals[productId];
    }

    /**
     * @dev Get transaction history for a product
     * @param _productId Product ID
     */
    function getProductHistory(uint256 _productId) 
        external 
        view 
        validProduct(_productId)
        returns (uint256[] memory) 
    {
        return pharmaceuticals[_productId].transactionHistory;
    }

    /**
     * @dev Get transaction details
     * @param _transactionId Transaction ID
     */
    function getTransaction(uint256 _transactionId) 
        external 
        view 
        returns (SupplyChainTransaction memory) 
    {
        require(transactions[_transactionId].transactionId != 0, "Transaction not found");
        return transactions[_transactionId];
    }

    /**
     * @dev Get quality checks for a product
     * @param _productId Product ID
     */
    function getProductQualityChecks(uint256 _productId) 
        external 
        view 
        validProduct(_productId)
        returns (uint256[] memory) 
    {
        return productQualityChecks[_productId];
    }

    /**
     * @dev Get quality check details
     * @param _checkId Quality check ID
     */
    function getQualityCheck(uint256 _checkId) 
        external 
        view 
        returns (QualityCheck memory) 
    {
        require(qualityChecks[_checkId].checkId != 0, "Quality check not found");
        return qualityChecks[_checkId];
    }

    /**
     * @dev Check if product is authentic (not counterfeit)
     * @param _productId Product ID
     * @param _batchNumber Batch number to verify
     */
    function verifyAuthenticity(uint256 _productId, string memory _batchNumber) 
        external 
        view 
        returns (bool) 
    {
        if (pharmaceuticals[_productId].productId == 0) {
            return false; // Product doesn't exist
        }
        
        return keccak256(bytes(pharmaceuticals[_productId].batchNumber)) == 
               keccak256(bytes(_batchNumber));
    }

    /**
     * @dev Get all products for an entity
     * @param _entity Entity address
     */
    function getEntityProducts(address _entity) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return entityProducts[_entity];
    }
}