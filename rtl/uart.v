module uart (
    input  wire        clk,
    input  wire        rst_n,
    // Configuration Registers
    input  wire [15:0] clks_per_bit, // Set this to (Freq/Baud)
    // Physical Lines
    input  wire        uart_rx,
    output reg         uart_tx,
    // Internal Interface
    output reg  [7:0]  rx_byte_out,
    output reg         rx_done_tick,
    input  wire [7:0]  tx_byte_in,
    input  wire        tx_start,
    output reg         tx_busy
);
    // --- Shared State Encodings ---
    localparam IDLE  = 2'b00,
               START = 2'b01,
               DATA  = 2'b10,
               STOP  = 2'b11;

    // --- RX Logic ---
    reg [1:0]  rx_state;
    reg [15:0] rx_clk_count;
    reg [2:0]  rx_bit_index;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state     <= IDLE;
            rx_done_tick <= 0;
        end else begin
            rx_done_tick <= 0; // Default pulse

            case (rx_state)
                IDLE: begin
                    if (uart_rx == 1'b0) begin // Start bit detected
                        rx_clk_count <= 0;
                        rx_state     <= START;
                    end
                end
                START: begin
                    if (rx_clk_count == (clks_per_bit >> 1)) begin // Sample in middle
                        if (uart_rx == 1'b0) begin
                            rx_clk_count <= 0;
                            rx_bit_index <= 0;
                            rx_state     <= DATA;
                        end else rx_state <= IDLE;
                    end else rx_clk_count <= rx_clk_count + 1;
                end
                DATA: begin
                    if (rx_clk_count < clks_per_bit - 1) begin
                        rx_clk_count <= rx_clk_count + 1;
                    end else begin
                        rx_clk_count            <= 0;
                        rx_byte_out[rx_bit_index] <= uart_rx;
                        if (rx_bit_index < 7) rx_bit_index <= rx_bit_index + 1;
                        else                  rx_state     <= STOP;
                    end
                end
                STOP: begin
                    if (rx_clk_count < clks_per_bit - 1) rx_clk_count <= rx_clk_count + 1;
                    else begin
                        rx_done_tick <= 1; // Raise internal flag
                        rx_state     <= IDLE;
                    end
                end
            endcase
        end
    end

    // --- TX Logic ---
    reg [1:0]  tx_state;
    reg [15:0] tx_clk_count;
    reg [2:0]  tx_bit_index;
    reg [7:0]  tx_shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_state     <= IDLE;
            tx_clk_count <= 0;
            tx_bit_index <= 0;
            tx_shift_reg <= 0;
            uart_tx      <= 1'b1; // Line idle high
            tx_busy      <= 1'b0;
        end else begin
            case (tx_state)
                IDLE: begin
                    uart_tx <= 1'b1; // Keep line high
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_shift_reg <= tx_byte_in;
                        tx_clk_count <= 0;
                        tx_busy      <= 1'b1;
                        tx_state     <= START;
                    end
                end
                START: begin
                    uart_tx <= 1'b0; // Drive start bit low
                    if (tx_clk_count < clks_per_bit - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        tx_bit_index <= 0;
                        tx_state     <= DATA;
                    end
                end
                DATA: begin
                    uart_tx <= tx_shift_reg[tx_bit_index]; // LSB first
                    if (tx_clk_count < clks_per_bit - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        if (tx_bit_index < 7) tx_bit_index <= tx_bit_index + 1;
                        else                  tx_state     <= STOP;
                    end
                end
                STOP: begin
                    uart_tx <= 1'b1; // Drive stop bit high
                    if (tx_clk_count < clks_per_bit - 1) begin
                        tx_clk_count <= tx_clk_count + 1;
                    end else begin
                        tx_clk_count <= 0;
                        tx_state     <= IDLE;
                    end
                end
            endcase
        end
    end
    
    // TX debug
    always @(posedge rx_done_tick) begin
	`print("UART", $sformatf(" RX : Received Byte: %h", rx_byte_out))
    end
    // RX debug
    always @(negedge tx_busy) begin
    	`print("UART", $sformatf(" TX : Transmitted Byte: %h", tx_byte_in))
    end


endmodule

