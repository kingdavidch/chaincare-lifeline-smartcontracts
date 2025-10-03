// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ClinicAppointments
 * @dev Smart contract for managing clinic consultations, appointments, and scheduling in ChainCare ecosystem
 * Provides comprehensive booking system for healthcare consultations
 */
contract ClinicAppointments is AccessControl, ReentrancyGuard {
    using Counters for Counters.Counter;

    bytes32 public constant PATIENT_ROLE = keccak256("PATIENT_ROLE");
    bytes32 public constant DOCTOR_ROLE = keccak256("DOCTOR_ROLE");
    bytes32 public constant CLINIC_ADMIN_ROLE = keccak256("CLINIC_ADMIN_ROLE");
    bytes32 public constant NURSE_ROLE = keccak256("NURSE_ROLE");

    enum AppointmentStatus {
        Scheduled,
        Confirmed,
        InProgress,
        Completed,
        Cancelled,
        NoShow,
        Rescheduled
    }

    enum ConsultationType {
        GeneralConsultation,
        FollowUp,
        Emergency,
        Specialist,
        Telemedicine,
        Vaccination,
        HealthCheckup,
        LabResults
    }

    enum TimeSlotStatus {
        Available,
        Booked,
        Blocked,
        Break
    }

    struct Clinic {
        uint256 clinicId;
        address clinicAddress;
        string name;
        string location;
        string[] services;
        string contactInfo;
        bool isActive;
        uint256 registrationDate;
        address[] doctors;
        string operatingHours; // "08:00-17:00"
        string[] operatingDays; // ["Monday", "Tuesday", ...]
        uint256 consultationFee;
        bool acceptsInsurance;
    }

    struct Doctor {
        address doctorAddress;
        uint256 clinicId;
        string name;
        string specialization;
        string licenseNumber;
        bool isAvailable;
        uint256 consultationFee;
        string[] availableDays; // ["Monday", "Wednesday", "Friday"]
        string[] timeSlots; // ["09:00", "10:00", "11:00", ...]
        uint256 experienceYears;
        string qualifications;
        uint256 rating; // Out of 100
        uint256 totalConsultations;
    }

    struct TimeSlot {
        uint256 slotId;
        address doctor;
        uint256 clinicId;
        string date; // "2025-10-15"
        string time; // "14:00"
        TimeSlotStatus status;
        uint256 duration; // in minutes
        uint256 fee;
    }

    struct Appointment {
        uint256 appointmentId;
        address patient;
        address doctor;
        uint256 clinicId;
        uint256 timeSlotId;
        ConsultationType consultationType;
        AppointmentStatus status;
        string appointmentDate;
        string appointmentTime;
        uint256 scheduledDate; // timestamp
        uint256 duration; // in minutes
        string patientNotes;
        string doctorNotes;
        string symptoms;
        uint256 consultationFee;
        bool isPaid;
        string paymentMethod; // "insurance", "cash", "stablecoin"
        uint256 createdAt;
        uint256 updatedAt;
        string[] attachments; // IPFS hashes for documents
        bool isEmergency;
        string followUpInstructions;
    }

    struct ConsultationRecord {
        uint256 consultationId;
        uint256 appointmentId;
        address patient;
        address doctor;
        uint256 startTime;
        uint256 endTime;
        string diagnosis;
        string prescription;
        string[] tests; // Lab tests ordered
        string nextAppointment; // Follow-up date
        string consultationNotes;
        bool isCompleted;
        uint256 medicalRecordId; // Link to PatientRecord contract
    }

    struct PatientQueue {
        uint256 queueId;
        uint256 clinicId;
        address[] patients;
        string date;
        mapping(address => uint256) patientPosition;
        mapping(address => uint256) estimatedWaitTime;
        uint256 currentPatientIndex;
    }

    Counters.Counter private clinicIdCounter;
    Counters.Counter private appointmentIdCounter;
    Counters.Counter private slotIdCounter;
    Counters.Counter private consultationIdCounter;
    Counters.Counter private queueIdCounter;

    mapping(uint256 => Clinic) public clinics;
    mapping(address => Doctor) public doctors;
    mapping(uint256 => TimeSlot) public timeSlots;
    mapping(uint256 => Appointment) public appointments;
    mapping(uint256 => ConsultationRecord) public consultations;
    mapping(uint256 => PatientQueue) public queues;
    
    mapping(address => uint256[]) public patientAppointments;
    mapping(address => uint256[]) public doctorAppointments;
    mapping(uint256 => uint256[]) public clinicAppointments;
    mapping(address => uint256) public doctorToClinic;
    mapping(uint256 => uint256[]) public clinicTimeSlots;
    mapping(string => uint256[]) public dailySlots; // date => slotIds
    mapping(address => bool) public registeredClinics;
    mapping(address => bool) public registeredDoctors;

    event ClinicRegistered(uint256 indexed clinicId, address indexed clinicAddress, string name);
    event DoctorRegistered(address indexed doctor, uint256 indexed clinicId, string specialization);
    event TimeSlotsCreated(address indexed doctor, uint256 indexed clinicId, string date, uint256 slotsCount);
    event AppointmentBooked(
        uint256 indexed appointmentId,
        address indexed patient,
        address indexed doctor,
        uint256 clinicId,
        string date,
        string time
    );
    event AppointmentCancelled(uint256 indexed appointmentId, address indexed cancelledBy, string reason);
    event AppointmentCompleted(uint256 indexed appointmentId, uint256 consultationId);
    event ConsultationStarted(uint256 indexed consultationId, uint256 indexed appointmentId);
    event ConsultationCompleted(uint256 indexed consultationId, string diagnosis);
    event PatientCheckedIn(uint256 indexed appointmentId, address indexed patient, uint256 queuePosition);
    event EmergencyAppointment(uint256 indexed appointmentId, address indexed patient, address indexed doctor);

    modifier onlyRegisteredClinic() {
        require(registeredClinics[msg.sender], "Clinic not registered");
        _;
    }

    modifier onlyRegisteredDoctor() {
        require(registeredDoctors[msg.sender], "Doctor not registered");
        _;
    }

    modifier validAppointment(uint256 _appointmentId) {
        require(appointments[_appointmentId].appointmentId != 0, "Appointment does not exist");
        _;
    }

    modifier validClinic(uint256 _clinicId) {
        require(clinics[_clinicId].clinicId != 0, "Clinic does not exist");
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        clinicIdCounter.increment(); // Start from 1
        appointmentIdCounter.increment();
        slotIdCounter.increment();
        consultationIdCounter.increment();
        queueIdCounter.increment();
    }

    /**
     * @dev Register a new clinic
     */
    function registerClinic(
        string memory _name,
        string memory _location,
        string[] memory _services,
        string memory _contactInfo,
        string memory _operatingHours,
        string[] memory _operatingDays,
        uint256 _consultationFee,
        bool _acceptsInsurance
    ) external {
        require(!registeredClinics[msg.sender], "Clinic already registered");
        require(bytes(_name).length > 0, "Name cannot be empty");

        uint256 clinicId = clinicIdCounter.current();
        clinicIdCounter.increment();

        clinics[clinicId] = Clinic({
            clinicId: clinicId,
            clinicAddress: msg.sender,
            name: _name,
            location: _location,
            services: _services,
            contactInfo: _contactInfo,
            isActive: true,
            registrationDate: block.timestamp,
            doctors: new address[](0),
            operatingHours: _operatingHours,
            operatingDays: _operatingDays,
            consultationFee: _consultationFee,
            acceptsInsurance: _acceptsInsurance
        });

        registeredClinics[msg.sender] = true;
        _grantRole(CLINIC_ADMIN_ROLE, msg.sender);

        emit ClinicRegistered(clinicId, msg.sender, _name);
    }

    /**
     * @dev Register a doctor to a clinic
     */
    function registerDoctor(
        address _doctorAddress,
        uint256 _clinicId,
        string memory _name,
        string memory _specialization,
        string memory _licenseNumber,
        uint256 _consultationFee,
        string[] memory _availableDays,
        string[] memory _timeSlots,
        uint256 _experienceYears,
        string memory _qualifications
    ) external validClinic(_clinicId) {
        require(
            clinics[_clinicId].clinicAddress == msg.sender || hasRole(CLINIC_ADMIN_ROLE, msg.sender),
            "Not authorized to register doctor"
        );
        require(!registeredDoctors[_doctorAddress], "Doctor already registered");

        doctors[_doctorAddress] = Doctor({
            doctorAddress: _doctorAddress,
            clinicId: _clinicId,
            name: _name,
            specialization: _specialization,
            licenseNumber: _licenseNumber,
            isAvailable: true,
            consultationFee: _consultationFee,
            availableDays: _availableDays,
            timeSlots: _timeSlots,
            experienceYears: _experienceYears,
            qualifications: _qualifications,
            rating: 80, // Default rating
            totalConsultations: 0
        });

        clinics[_clinicId].doctors.push(_doctorAddress);
        doctorToClinic[_doctorAddress] = _clinicId;
        registeredDoctors[_doctorAddress] = true;
        
        _grantRole(DOCTOR_ROLE, _doctorAddress);

        emit DoctorRegistered(_doctorAddress, _clinicId, _specialization);
    }

    /**
     * @dev Create time slots for a doctor
     */
    function createTimeSlots(
        address _doctor,
        string memory _date,
        string[] memory _times,
        uint256 _duration,
        uint256 _fee
    ) external onlyRegisteredDoctor {
        require(
            msg.sender == _doctor || 
            clinics[doctorToClinic[_doctor]].clinicAddress == msg.sender,
            "Not authorized to create slots"
        );
        require(registeredDoctors[_doctor], "Doctor not registered");

        uint256 clinicId = doctorToClinic[_doctor];
        
        for (uint256 i = 0; i < _times.length; i++) {
            uint256 slotId = slotIdCounter.current();
            slotIdCounter.increment();

            timeSlots[slotId] = TimeSlot({
                slotId: slotId,
                doctor: _doctor,
                clinicId: clinicId,
                date: _date,
                time: _times[i],
                status: TimeSlotStatus.Available,
                duration: _duration,
                fee: _fee
            });

            clinicTimeSlots[clinicId].push(slotId);
            dailySlots[_date].push(slotId);
        }

        emit TimeSlotsCreated(_doctor, clinicId, _date, _times.length);
    }

    /**
     * @dev Book an appointment
     */
    function bookAppointment(
        address _doctor,
        uint256 _timeSlotId,
        ConsultationType _consultationType,
        string memory _symptoms,
        string memory _patientNotes,
        string[] memory _attachments,
        bool _isEmergency
    ) external nonReentrant {
        require(timeSlots[_timeSlotId].status == TimeSlotStatus.Available, "Time slot not available");
        require(timeSlots[_timeSlotId].doctor == _doctor, "Doctor mismatch");
        require(registeredDoctors[_doctor], "Doctor not registered");

        TimeSlot storage slot = timeSlots[_timeSlotId];
        uint256 clinicId = slot.clinicId;
        
        // Mark slot as booked
        slot.status = TimeSlotStatus.Booked;

        uint256 appointmentId = appointmentIdCounter.current();
        appointmentIdCounter.increment();

        appointments[appointmentId] = Appointment({
            appointmentId: appointmentId,
            patient: msg.sender,
            doctor: _doctor,
            clinicId: clinicId,
            timeSlotId: _timeSlotId,
            consultationType: _consultationType,
            status: AppointmentStatus.Scheduled,
            appointmentDate: slot.date,
            appointmentTime: slot.time,
            scheduledDate: block.timestamp,
            duration: slot.duration,
            patientNotes: _patientNotes,
            doctorNotes: "",
            symptoms: _symptoms,
            consultationFee: slot.fee,
            isPaid: false,
            paymentMethod: "",
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            attachments: _attachments,
            isEmergency: _isEmergency,
            followUpInstructions: ""
        });

        patientAppointments[msg.sender].push(appointmentId);
        doctorAppointments[_doctor].push(appointmentId);
        clinicAppointments[clinicId].push(appointmentId);

        _grantRole(PATIENT_ROLE, msg.sender);

        emit AppointmentBooked(appointmentId, msg.sender, _doctor, clinicId, slot.date, slot.time);

        if (_isEmergency) {
            emit EmergencyAppointment(appointmentId, msg.sender, _doctor);
        }
    }

    /**
     * @dev Cancel an appointment
     */
    function cancelAppointment(uint256 _appointmentId, string memory _reason) 
        external 
        validAppointment(_appointmentId) 
    {
        Appointment storage appointment = appointments[_appointmentId];
        require(
            appointment.patient == msg.sender ||
            appointment.doctor == msg.sender ||
            clinics[appointment.clinicId].clinicAddress == msg.sender,
            "Not authorized to cancel appointment"
        );
        require(
            appointment.status == AppointmentStatus.Scheduled ||
            appointment.status == AppointmentStatus.Confirmed,
            "Cannot cancel appointment in current status"
        );

        appointment.status = AppointmentStatus.Cancelled;
        appointment.updatedAt = block.timestamp;

        // Free up the time slot
        timeSlots[appointment.timeSlotId].status = TimeSlotStatus.Available;

        emit AppointmentCancelled(_appointmentId, msg.sender, _reason);
    }

    /**
     * @dev Confirm an appointment
     */
    function confirmAppointment(uint256 _appointmentId) 
        external 
        validAppointment(_appointmentId) 
    {
        Appointment storage appointment = appointments[_appointmentId];
        require(
            appointment.doctor == msg.sender ||
            clinics[appointment.clinicId].clinicAddress == msg.sender,
            "Not authorized to confirm appointment"
        );
        require(appointment.status == AppointmentStatus.Scheduled, "Appointment not scheduled");

        appointment.status = AppointmentStatus.Confirmed;
        appointment.updatedAt = block.timestamp;
    }

    /**
     * @dev Check in patient for appointment
     */
    function checkInPatient(uint256 _appointmentId) 
        external 
        validAppointment(_appointmentId) 
    {
        Appointment storage appointment = appointments[_appointmentId];
        require(
            appointment.patient == msg.sender ||
            clinics[appointment.clinicId].clinicAddress == msg.sender ||
            hasRole(NURSE_ROLE, msg.sender),
            "Not authorized to check in patient"
        );
        require(appointment.status == AppointmentStatus.Confirmed, "Appointment not confirmed");

        // Add to queue logic here
        uint256 queuePosition = _addToQueue(appointment.clinicId, appointment.patient, appointment.appointmentDate);
        
        emit PatientCheckedIn(_appointmentId, appointment.patient, queuePosition);
    }

    /**
     * @dev Start consultation
     */
    function startConsultation(uint256 _appointmentId) 
        external 
        onlyRegisteredDoctor 
        validAppointment(_appointmentId) 
    {
        Appointment storage appointment = appointments[_appointmentId];
        require(appointment.doctor == msg.sender, "Not your appointment");
        require(
            appointment.status == AppointmentStatus.Confirmed ||
            appointment.status == AppointmentStatus.Scheduled,
            "Appointment not ready for consultation"
        );

        appointment.status = AppointmentStatus.InProgress;
        appointment.updatedAt = block.timestamp;

        uint256 consultationId = consultationIdCounter.current();
        consultationIdCounter.increment();

        consultations[consultationId] = ConsultationRecord({
            consultationId: consultationId,
            appointmentId: _appointmentId,
            patient: appointment.patient,
            doctor: msg.sender,
            startTime: block.timestamp,
            endTime: 0,
            diagnosis: "",
            prescription: "",
            tests: new string[](0),
            nextAppointment: "",
            consultationNotes: "",
            isCompleted: false,
            medicalRecordId: 0
        });

        emit ConsultationStarted(consultationId, _appointmentId);
    }

    /**
     * @dev Complete consultation
     */
    function completeConsultation(
        uint256 _consultationId,
        string memory _diagnosis,
        string memory _prescription,
        string[] memory _tests,
        string memory _nextAppointment,
        string memory _consultationNotes,
        string memory _followUpInstructions
    ) external onlyRegisteredDoctor {
        ConsultationRecord storage consultation = consultations[_consultationId];
        require(consultation.doctor == msg.sender, "Not your consultation");
        require(!consultation.isCompleted, "Consultation already completed");

        consultation.diagnosis = _diagnosis;
        consultation.prescription = _prescription;
        consultation.tests = _tests;
        consultation.nextAppointment = _nextAppointment;
        consultation.consultationNotes = _consultationNotes;
        consultation.endTime = block.timestamp;
        consultation.isCompleted = true;

        // Update appointment
        Appointment storage appointment = appointments[consultation.appointmentId];
        appointment.status = AppointmentStatus.Completed;
        appointment.doctorNotes = _consultationNotes;
        appointment.followUpInstructions = _followUpInstructions;
        appointment.updatedAt = block.timestamp;

        // Update doctor statistics
        doctors[msg.sender].totalConsultations++;

        emit ConsultationCompleted(_consultationId, _diagnosis);
        emit AppointmentCompleted(consultation.appointmentId, _consultationId);
    }

    /**
     * @dev Get available time slots for a doctor on a specific date
     */
    function getAvailableSlots(address _doctor, string memory _date) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256[] memory daySlots = dailySlots[_date];
        uint256 availableCount = 0;
        
        // First pass: count available slots
        for (uint256 i = 0; i < daySlots.length; i++) {
            if (timeSlots[daySlots[i]].doctor == _doctor && 
                timeSlots[daySlots[i]].status == TimeSlotStatus.Available) {
                availableCount++;
            }
        }
        
        // Second pass: populate result array
        uint256[] memory availableSlots = new uint256[](availableCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < daySlots.length; i++) {
            if (timeSlots[daySlots[i]].doctor == _doctor && 
                timeSlots[daySlots[i]].status == TimeSlotStatus.Available) {
                availableSlots[index] = daySlots[i];
                index++;
            }
        }
        
        return availableSlots;
    }

    /**
     * @dev Get patient's appointments
     */
    function getPatientAppointments(address _patient) 
        external 
        view 
        returns (uint256[] memory) 
    {
        require(
            msg.sender == _patient || hasRole(CLINIC_ADMIN_ROLE, msg.sender),
            "Not authorized to view patient appointments"
        );
        return patientAppointments[_patient];
    }

    /**
     * @dev Get doctor's appointments
     */
    function getDoctorAppointments(address _doctor) 
        external 
        view 
        returns (uint256[] memory) 
    {
        require(
            msg.sender == _doctor || 
            clinics[doctorToClinic[_doctor]].clinicAddress == msg.sender,
            "Not authorized to view doctor appointments"
        );
        return doctorAppointments[_doctor];
    }

    /**
     * @dev Get clinic's appointments
     */
    function getClinicAppointments(uint256 _clinicId) 
        external 
        view 
        validClinic(_clinicId)
        returns (uint256[] memory) 
    {
        require(
            clinics[_clinicId].clinicAddress == msg.sender ||
            hasRole(CLINIC_ADMIN_ROLE, msg.sender),
            "Not authorized to view clinic appointments"
        );
        return clinicAppointments[_clinicId];
    }

    /**
     * @dev Search for doctors by specialization
     */
    function searchDoctorsBySpecialization(string memory _specialization) 
        external 
        view 
        returns (address[] memory) 
    {
        // This is a simplified implementation
        // In practice, you'd want to maintain a more efficient index
        address[] memory allDoctors = new address[](100); // Temporary array
        uint256 count = 0;
        
        // This would need to be implemented with proper indexing in production
        return allDoctors;
    }

    /**
     * @dev Rate a doctor after consultation
     */
    function rateDoctor(address _doctor, uint256 _rating, uint256 _appointmentId) 
        external 
        validAppointment(_appointmentId) 
    {
        require(_rating <= 100, "Rating must be between 0-100");
        require(appointments[_appointmentId].patient == msg.sender, "Not your appointment");
        require(appointments[_appointmentId].status == AppointmentStatus.Completed, "Appointment not completed");

        Doctor storage doctor = doctors[_doctor];
        // Simple rating calculation (could be more sophisticated)
        doctor.rating = (doctor.rating + _rating) / 2;
    }

    /**
     * @dev Internal function to add patient to queue
     */
    function _addToQueue(uint256 _clinicId, address _patient, string memory _date) 
        internal 
        returns (uint256) 
    {
        // Simplified queue implementation
        // In practice, this would be more sophisticated
        return 1; // Return queue position
    }

    /**
     * @dev Set doctor availability
     */
    function setDoctorAvailability(bool _isAvailable) external onlyRegisteredDoctor {
        doctors[msg.sender].isAvailable = _isAvailable;
    }

    /**
     * @dev Get clinic information
     */
    function getClinic(uint256 _clinicId) 
        external 
        view 
        validClinic(_clinicId)
        returns (Clinic memory) 
    {
        return clinics[_clinicId];
    }

    /**
     * @dev Get doctor information
     */
    function getDoctor(address _doctor) 
        external 
        view 
        returns (Doctor memory) 
    {
        require(registeredDoctors[_doctor], "Doctor not registered");
        return doctors[_doctor];
    }

    /**
     * @dev Get appointment details
     */
    function getAppointment(uint256 _appointmentId) 
        external 
        view 
        validAppointment(_appointmentId)
        returns (Appointment memory) 
    {
        return appointments[_appointmentId];
    }

    /**
     * @dev Get consultation record
     */
    function getConsultation(uint256 _consultationId) 
        external 
        view 
        returns (ConsultationRecord memory) 
    {
        require(consultations[_consultationId].consultationId != 0, "Consultation does not exist");
        require(
            consultations[_consultationId].patient == msg.sender ||
            consultations[_consultationId].doctor == msg.sender ||
            hasRole(CLINIC_ADMIN_ROLE, msg.sender),
            "Not authorized to view consultation"
        );
        return consultations[_consultationId];
    }
}