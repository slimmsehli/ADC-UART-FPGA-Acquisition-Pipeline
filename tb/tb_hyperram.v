`timescale 1ps/1ps

module top;

    //--------------------------------------------------------------
    // Clock generation (free-running)
    //--------------------------------------------------------------
    reg CK = 1'b0;
    localparam CK_PERIOD = 10000;   // 100 MHz (10ns = 10000ps)
    always #(CK_PERIOD/2) CK <= ~CK;

    //--------------------------------------------------------------
    // HyperBus DUT I/O
    //--------------------------------------------------------------
    reg RESETNeg;
    reg CSNeg;

    // DQ
    reg  [7:0] DQ_out;
    reg        DQ_en;
    wire [7:0] DQ_bus = DQ_en ? DQ_out : 8'hZZ;

    // RWDS
    reg  RWDS_out;
    reg  RWDS_en;
    wire RWDS_bus = RWDS_en ? RWDS_out : 1'bZ;

    // Unused differential negative clock
    wire CKn = 1'b0;


    //--------------------------------------------------------------
    // Instantiate Infineon HyperRAM model (S80KS5122)
    //--------------------------------------------------------------
    s80ks5122 dut (
        .DQ7(DQ_bus[7]), .DQ6(DQ_bus[6]), .DQ5(DQ_bus[5]), .DQ4(DQ_bus[4]),
        .DQ3(DQ_bus[3]), .DQ2(DQ_bus[2]), .DQ1(DQ_bus[1]), .DQ0(DQ_bus[0]),
        .RWDS(RWDS_bus),
        .CSNeg(CSNeg),
        .CK(CK),
        .CKn(CKn),
        .RESETNeg(RESETNeg)
    );


    //--------------------------------------------------------------
    // Helper task: transmit CA (48 bits) MSB→LSB
    //--------------------------------------------------------------
    task send_CA(input [47:0] CA);
        integer i;
        DQ_out = 8'h00;
        begin
            DQ_en = 1'b1;
            for (i = 47; i >= 0; i -= 8) begin
                @(negedge CK); DQ_out = CA[i -: 8]; $display("WRITE : sending CA[]=%b", CA[i -: 8]);
                @(posedge CK);
            end
            @(negedge CK);
            DQ_en = 1'b0;
        end
    endtask


    //--------------------------------------------------------------
    // Helper task: write 16-bit data (DDR)
    //--------------------------------------------------------------
    task write_word(input [15:0] W);
        begin
            RWDS_en  = 1;
            RWDS_out = 0;   // 0 ⇒ write both bytes

            DQ_en = 1'b1;
            @(posedge CK); DQ_out = W[15:8];
            @(negedge CK); DQ_out = W[7:0];

            @(posedge CK);
            DQ_en   = 0;
            RWDS_en = 0;
        end
    endtask


    //--------------------------------------------------------------
    // Helper task: read 16‑bit data (DDR using RWDS strobe)
    //--------------------------------------------------------------
    task read_word(output [15:0] R);
    reg [7:0] hi, lo;

    begin
        // Make sure controller is not driving
        DQ_en   = 0;
        RWDS_en = 0;

        // ---------- WAIT FOR LATENCY ----------
        // In fixed-latency mode, RWDS HIGH indicates latency completion.
        @(posedge RWDS_bus);  // when RWDS finally rises

        // ---------- CAPTURE DATA ----------
        @(posedge CK); hi = DQ_bus;
        @(negedge CK); lo = DQ_bus;

        R = {hi, lo};
    end
		endtask


    //--------------------------------------------------------------
    // Test sequence (WRITE → READ BACK)
    //--------------------------------------------------------------
    reg [31:0] addr;
    reg [15:0] write_data;
    reg [15:0] read_data;
    reg [47:0] CA;

    initial begin
        //----------------------------------------------------------
        // Initial defaults
        //----------------------------------------------------------
        CSNeg     = 1;
        RESETNeg  = 0;
        DQ_en     = 0;
        RWDS_en   = 0;
        DQ_out    = 8'h00;
        RWDS_out  = 1'b0;

        //----------------------------------------------------------
        // Mandatory power‑up wait per model (tdevice_VCS = 150 µs)
        //----------------------------------------------------------
        #(200_000_000);  // 200 µs

        //----------------------------------------------------------
        // Release RESET#
        //----------------------------------------------------------
        @(negedge CK);
        RESETNeg = 1;
        #(300_000);  // 300ns extra guard time


        //----------------------------------------------------------
        // Prepare WRITE CA
        //----------------------------------------------------------
        addr        = 32'h00000010;
        write_data  = 16'hA5C3;

        CA = {
            1'b0,               // RW = 0 (write)
            1'b0,               // address space = memory
            1'b1,               // burst = linear
            addr[31:3],         // upper address bits
            13'h0000,           // reserved
            addr[2:0]           // lower 3 bits
        };
        $display("HYPERMEM - WRITE - CA=%h - %b", CA, CA);

        //----------------------------------------------------------
        // WRITE operation
        //----------------------------------------------------------
        @(negedge CK);
        #(10000/5);
        CSNeg <= 1'b0;
        @(negedge CK);   // ≥ one CK half‑cycle = tCSS satisfied

        send_CA(CA);
        write_word(write_data);

        @(negedge CK);
        CSNeg <= 1'b1;

        #(100_000);  // allow the RAM to settle (~100ns)


        //----------------------------------------------------------
        // Prepare READ CA
        //----------------------------------------------------------
        CA = {
            1'b1,               // RW = 1 (READ)
            1'b0,               // memory space
            1'b1,               // linear burst
            addr[31:3],
            13'h0000,
            addr[2:0]
        };
        $display("HYPERMEM - READ - CA=%h - %b", CA, CA);

        //----------------------------------------------------------
        // READ operation
        //----------------------------------------------------------
        @(negedge CK);
        CSNeg <= 1'b0;
        @(negedge CK);

        send_CA(CA);

        // Data will appear after fixed latency; RWDS strobes it
        read_word(read_data);

        @(negedge CK);
        CSNeg <= 1'b1;

        //----------------------------------------------------------
        // Show result
        //----------------------------------------------------------
        $display("\nWRITE = 0x%04h", write_data);
        $display("READ  = 0x%04h", read_data);

        #(50_000);
        $finish;
    end


    // Safety timeout
    initial begin
        #(10_000_000_000); // 10 ms
        $display("TIMEOUT");
        $finish;
    end

endmodule
