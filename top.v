module top;
		parameter CLK_PERIOD = 10;
    parameter MAX_CYCLES = 500_000_000;
    parameter GPIO_COUNT = 16;
    parameter MEM_WORDS  = 32768;
    parameter VERBOSE    = 0;
    
    // Bit periods at 115200 baud / 100 MHz clock
    localparam UART_HALF = 434;
    localparam UART_FULL = 868;
    
    // parametrs and signals ofr the UART
    parameter CLK_FREQUENCY = 100_000_000; // (MHz) FPGA clock : 100MHz
    parameter CLK_PERIOD_main = 10 ; // 10ps
    parameter BAUD_RATE  = 9600; //19200, 115200;
    parameter CPB  = CLK_FREQUENCY / BAUD_RATE ; //868;   // 100MHz / 115200
    parameter BIT_PERIOD  = CPB * CLK_PERIOD_main;
    reg clk_main    = 0;
    reg reset;
    always #(CLK_PERIOD_main/2) clk_main = ~clk_main;
    reg [15:0] baudrate;
    reg uart_rx;
    reg  [7:0]  rx_byte_out;
    wire rx_done_tick;
    wire         cmd_acquire;
    wire         cmd_read;    
    reg [7:0] command_list [0:3];
    integer i;
    
    // =========================================================================
    // ADC : a dummy ADC that generates a  signal at 10 bits at 60MHz 
    // =========================================================================
    parameter CLK_PERIOD_adc = 17; // 60MHz = 16ps period
    reg clk_adc    = 0;
    always #(CLK_PERIOD_adc/2) clk_adc = ~clk_adc;
    reg  [9:0] adc_data;
    reg enable_adc;
    adc adc_i (
		  .enable(enable_adc),
		  .adc_data(adc_data) //reg  [9:0] 
    );
    
    // =========================================================================
    // UART with decoder
    // =========================================================================

    uart_decoder_top uart_decoder_top_i (
			.clk(clk_main), //input  wire        clk,
			.rst_n(reset), //input  wire        rst_n,
			// Configuration Registers
			.clks_per_bit(baudrate), //input  wire [15:0] clks_per_bit(baudrate),
			// Physical Lines
			.uart_rx(uart_rx),
			.uart_tx(uart_tx),
			// Internal Interface
			.rx_byte_out(rx_byte_out), //output reg  [7:0]  rx_byte_out,
			.rx_done_tick(rx_done_tick), //output reg         rx_done_tick,
			//.tx_byte_in(tx_byte_in), //input  wire [7:0]  tx_byte_in,
			//.(tx_start) //input  wire        tx_start
			// decoder output
		  .cmd_acquire(cmd_acquire), //output reg         cmd_start,
		  .cmd_read(cmd_read) //output reg         cmd_stop
		);
		
		// logic to activate or not the ADC based on the UART signals 
		always @(posedge clk) begin
			if (cmd_acquire)
				enable_adc = 1'b1;
			
			if (cmd_read)
				enable_adc = 1'b0;
		end
		
		
    
    
    // =========================================================================
    // TB
    // =========================================================================
    
    // UART TX task 
    task send_uart_byte(input [7:0] data);
        integer bit_idx;
        begin
            // Start Bit (Low)
            uart_rx = 0;
            #(BIT_PERIOD);
            
            // Data Bits (LSB first)
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                uart_rx = data[bit_idx];
                #(BIT_PERIOD);
            end
            
            // Stop Bit (High)
            uart_rx = 1;
            #(BIT_PERIOD);
            `print("TB", $sformatf("Sent Byte: %h ('%c') ", data, data))
        end
    endtask
    
    initial begin
		  $display("=================================================");
		  $display("[TB]   ADC AQUISITION  ");
		  $display("[TB]   FPGA CLOCK : 100MHz  ");
		  $display("[TB]   ADC CLOCK : 60MHz  ");
		  $display("[TB]   UART BAUDRATE : %d  ", BAUD_RATE);
		  $display("=================================================");
		  reset = 0;
		  uart_rx = 1;
		  baudrate = CPB;
		  // Populate Command List
		  command_list[0] = 8'h61; // 'a' (Acquire)
		  command_list[1] = 8'h72; // 'r' (Read)
		  command_list[2] = 8'h73; // 's' (Status)
		  command_list[3] = 8'h74; // 't' (Test)
		  
		  // Reset the System
		  #(CLK_PERIOD_main * 10);
		  reset = 1;
		  #(CLK_PERIOD_main * 10);
		  
		  // --- Test "acquire" ---
		  send_uart_byte(8'h61); // a
		  send_uart_byte(8'h63); // c
		  send_uart_byte(8'h71); // q
		  send_uart_byte(8'h75); // u
		  send_uart_byte(8'h69); // i
		  send_uart_byte(8'h72); // r
		  send_uart_byte(8'h65); // e
		  send_uart_byte(8'h20); // SPACE (Triggers the command)
		  
		  #(BIT_PERIOD * 20); // Wait for processing

		  // --- Test "read" ---
		  send_uart_byte(8'h72); // r
		  send_uart_byte(8'h65); // e
		  send_uart_byte(8'h61); // a
		  send_uart_byte(8'h64); // d
		  send_uart_byte(8'h20); // SPACE

		  #(BIT_PERIOD * 10);
		  $display("=================================================");
		  $display("[TB] Simulation Finished");
		  $display("=================================================");
		  $finish;
    end
    
    
    
    
    
    
    
    
    
    
    
    
    
		
		
		// =========================================================================
    // UART TX monitor — decodes serial from the real TX pad
    // =========================================================================
    reg uart_pad_tx; // uart rx pin
    integer uart_state = 0;
    integer uart_cnt   = 0;
    integer uart_bit   = 0;
    reg [7:0] uart_byte = 0;

    always @(posedge clk) begin
        case (uart_state)
            0: if (uart_pad_tx == 1'b0) begin
                uart_state <= 1;
                uart_cnt   <= UART_HALF;
            end
            1: if (uart_cnt == 0) begin
                uart_state <= 2;
                uart_cnt   <= UART_FULL;
                uart_bit   <= 0;
            end else uart_cnt <= uart_cnt - 1;
            2: if (uart_cnt == 0) begin
                uart_cnt <= UART_FULL;
                if (uart_bit < 8) begin
                    uart_byte <= {uart_pad_tx, uart_byte[7:1]};
                    uart_bit  <= uart_bit + 1;
                end else begin
                    $write("%c", uart_byte);
                    uart_state <= 0;
                end
            end else uart_cnt <= uart_cnt - 1;
        endcase
    end

		string vcd_file;
		initial begin
        //if (!$value$plusargs("MEM_FILE=%s", mem_file_padded))
        //    mem_file_padded = "firmware.hex";
        if (!$value$plusargs("VCD_FILE=%s", vcd_file))
            vcd_file = "waves.vcd";
        //mem_file = mem_file_padded[255:0];
        //vcd_file = vcd_file_padded[255:0];
    end
    
    // =========================================================================
    // Clock & Reset
    // =========================================================================
    reg clk    = 0;
    reg resetn = 0;
    always #(CLK_PERIOD/2) clk = ~clk;
    initial begin repeat(8) @(posedge clk); resetn = 1; end
    //initial begin repeat(100) @(posedge clk); $finish; end
    
    // =========================================================================
    // VCD
    // =========================================================================
    initial begin
        #1;
        $dumpfile(vcd_file);
        $dumpvars(0, top);
    end

endmodule
