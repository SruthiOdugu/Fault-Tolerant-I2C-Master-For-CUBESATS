module i2c_master(
    input wire clk,
    input wire [6:0] addr, 
    input wire [7:0] data_in,
    input wire rst,
    input wire enable,
    input wire rw, 

    output reg [7:0] data_out, 
    output wire ready, 

    inout i2c_scl,
    inout i2c_sda 
);

localparam IDLE = 0;
localparam START = 1;
localparam ADDRESS = 2;
localparam READ_ACK = 3; 
localparam WRITE_DATA = 4;
localparam WRITE_ACK = 5;
localparam READ_DATA = 6;
localparam READ_ACK2 = 7; 
localparam STOP = 8;

localparam DIVIDE_BY = 20;

reg [7:0] state;
reg [7:0] saved_addr; 
reg [7:0] saved_data; 
reg [7:0] counter;
reg [7:0] counter2 = 0; 
reg write_enable; 
reg sda_out; 
reg i2c_scl_enable = 0; 
reg i2c_clk = 1; 

reg [2:0] sda_sr = 3'b111; 
reg filtered_sda = 1;     

always @(posedge clk or posedge rst) begin
    if (rst == 1) begin
        sda_sr <= 3'b111;
        filtered_sda <= 1'b1;
    end else begin
        sda_sr <= {sda_sr[1:0], i2c_sda}; 

        if ({sda_sr[1:0], i2c_sda} == 3'b111) begin
            filtered_sda <= 1'b1;
        end else if ({sda_sr[1:0], i2c_sda} == 3'b000) begin
            filtered_sda <= 1'b0;
        end
    end
end

assign ready = ((rst==0) && (state == IDLE)) ? 1 : 0;
assign i2c_scl = (i2c_scl_enable == 0) ? 1 : i2c_clk;
assign i2c_sda = (write_enable == 1 && sda_out == 0) ? 1'b0 : 1'bz;

always @(negedge i2c_clk, posedge rst) begin
    if (rst == 1) begin
        write_enable <= 1;
        sda_out      <= 1;
    end else begin
        if ((state == READ_ACK) || (state == READ_DATA) || (state == WRITE_ACK)) begin
            write_enable <= 0;
        end else begin
            write_enable <= 1;
        end

        if (state == START || state == STOP) begin
            sda_out <= 0;
        end else if (state == ADDRESS) begin
            sda_out <= saved_addr[counter];
        end else if (state == WRITE_DATA) begin
            sda_out <= saved_data[counter];
        end else begin
            sda_out <= 1;
        end
    end
end

always @(posedge clk) begin 
    if (counter2 == (DIVIDE_BY/2) - 1) begin 
        i2c_clk <= ~i2c_clk;
        counter2 <= 0; 
    end
    else counter2 <= counter2 + 1;
end

always @(negedge i2c_clk, posedge rst) begin 
    if (rst == 1) begin
        i2c_scl_enable <= 0;
    end else begin
        if ((state == IDLE) || (state == START) || (state == STOP)) begin
            i2c_scl_enable <= 0;
        end else begin
            i2c_scl_enable <= 1;
        end
    end
end

always @(posedge i2c_clk, posedge rst) begin
    if(rst == 1) begin
        state <= IDLE;
    end
    else begin
        case(state)

            IDLE: begin        
                if (enable) begin
                    state <= START;
                    saved_addr <= {addr, rw}; 
                    saved_data <= data_in;
                end
                else state <= IDLE;
            end

            START: begin
                counter <= 7; 
                state   <= ADDRESS;
            end

            ADDRESS: begin

                if (counter == 0) begin
                    state <= READ_ACK;
                end else counter <= counter - 1; 
            end

            READ_ACK: begin
                if (filtered_sda == 0) begin 
                    counter <= 7;
                    if(saved_addr[0] == 0) state <= WRITE_DATA; 
                    else state <= READ_DATA;
                end else begin
                     state <= STOP;
                end
            end

            WRITE_DATA: begin
                if (counter == 0) begin
                    state <= WRITE_ACK; 
                end else counter <= counter - 1;
            end
            
            WRITE_ACK: begin
                 if (filtered_sda == 0) state <= STOP;
                 else state <= STOP;
            end

            READ_DATA: begin
                data_out[counter] <= filtered_sda;
                if (counter == 0) state <= READ_ACK2;
                else counter <= counter - 1;
            end

            READ_ACK2: begin
            state <= STOP; 
            end

            STOP: begin
                state <= IDLE;
            end
            
        endcase
    end 
end 

endmodule 
