---

# FPGA High-Speed ADC Acquisition Pipeline
Capture 60 MSPS ADC data, buffer via FIFO, store to HyperRAM, and retrieve through a UART CLI.

---

# Overview
This project implements a high‑speed data acquisition pipeline on an FPGA connected to an external ADC sampling at **60 MSPS**.  
The FPGA operates at **100 MHz**, managing the capture, buffering, storage, and extraction of digitized samples.

---

# Architecture

### **1. ADC Interface – 60 MSPS**
- The external ADC continuously generates samples at **60 million samples per second**.
- On `acquire`, the FPGA enables the ADC capture logic.

### **2. FIFO Buffer (High‑Speed Domain)**
- Temporary FIFO stores samples clocked at **60 MHz** to buffer the data between the 60MHz data in and the main FPGA clock at 100MHz.

### **3. HyperRAM Storage**
- Captured data is transferred from FIFO to HyperRAM with 10k values are captured and stored

### **4. UART CLI **
- UART provides full user control using simple ASCII commands, one to start the acquisition and the other one to read back the data to the uart



