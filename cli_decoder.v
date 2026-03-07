module cli_decoder (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  rx_byte,      // From UART rx_byte_out
    input  wire        rx_done_tick, // From UART rx_done_tick
    output reg         cmd_acquire,  // High for 1 cycle on "acquire"
    output reg         cmd_read      // High for 1 cycle on "read"
);

    reg [63:0] token_buffer; // Holds up to 8 characters

    // Command Hex Definitions (Right-aligned ASCII)
    // "acquire" = 61 63 71 75 69 72 65
    localparam CMD_ACQUIRE = 56'h61_63_71_75_69_72_65; 
    // "read"    = 72 65 61 64
    localparam CMD_READ    = 32'h72_65_61_64;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            token_buffer <= 64'h0;
            cmd_acquire  <= 0;
            cmd_read     <= 0;
        end else begin
            cmd_acquire <= 0; // Pulse behavior
            cmd_read    <= 0;

            if (rx_done_tick) begin
                // Check for terminator: Space (0x20), CR (0x0D), or LF (0x0A)
                if (rx_byte == 8'h20 || rx_byte == 8'h0D || rx_byte == 8'h0A) begin
                    
                    // Match "acquire" (Checking the last 7 bytes of the buffer)
                    if (token_buffer[55:0] == CMD_ACQUIRE) begin
                        cmd_acquire <= 1;
                    end 
                    // Match "read" (Checking the last 4 bytes of the buffer)
                    else if (token_buffer[31:0] == CMD_READ) begin
                        cmd_read <= 1;
                    end
                    
                    token_buffer <= 64'h0; // Clear buffer for next word
                end 
                else begin
                    // Shift in the new character
                    token_buffer <= {token_buffer[55:0], rx_byte};
                end
            end
        end
    end
endmodule
