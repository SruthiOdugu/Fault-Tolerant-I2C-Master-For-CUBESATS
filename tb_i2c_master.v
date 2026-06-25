module tb_i2c_master;
    reg clk;
    reg rst;
    reg enable;
    reg rw;
    reg [6:0] addr;
    reg [7:0] data_in;
    wire [7:0] data_out;
    wire ready;
    wire i2c_sda;
    wire i2c_scl;
    reg tb_sda_drive; 
    
    reg prev_scl = 1; 
    
        always @(i2c_scl) begin
            prev_scl <= i2c_scl;
        end

    assign i2c_sda = (tb_sda_drive === 1'b0) ? 1'b0 : 1'bz;
    
    i2c_master uut (
        .clk(clk), 
        .rst(rst), 
        .addr(addr), 
        .data_in(data_in), 
        .enable(enable), 
        .rw(rw), 
        .data_out(data_out), 
        .ready(ready), 
        .i2c_scl(i2c_scl), 
        .i2c_sda(i2c_sda)
    );

    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end
    

        pullup(i2c_sda);
        pullup(i2c_scl);
        
    initial begin
        rst = 1;
        enable = 0;
        rw = 0;
        addr = 0;
        data_in = 0;
        tb_sda_drive = 1'bz;

        #100;
        rst = 0;
        #100;

        $display("Starting Transaction...");
                addr = 7'h50;    //1001000  
                data_in = 8'hAB; //10101011  
                rw = 0;            
                enable = 1;        
                #500 enable = 0; //internal i2c clk = 400ns (2.5Mhz)
                
                #3600; 
                $display("Radiation Strike! Forcing SDA High.");
                
                force i2c_sda = 1'b1; 
                
                #15; 
                
                release i2c_sda; 
                $display("Radiation Passed. Bus restored.");
        
                #6000; 
        
                $display("Starting Read Transaction...");
                addr = 7'h50;  
                rw = 1;            
                enable = 1;        
                #500 enable = 0;  
    end




integer bit_count = 0;
reg [7:0] slave_tx_data = 8'hC3; //1100011
reg in_transaction = 0;


always @(negedge i2c_sda) begin
    #1;
    if (i2c_scl === 1'b1 && in_transaction == 0) begin
        in_transaction = 1;
        bit_count = 0;        
    end
end

always @(posedge i2c_sda) begin
    #1;
    if (i2c_scl === 1'b1) begin
        in_transaction = 0;   
    end
end

always @(negedge i2c_scl) begin
    #2;
    if (in_transaction) begin
        bit_count = bit_count + 1;  

        if (bit_count <= 8) begin
            tb_sda_drive <= 1'bz;

        end else if (bit_count == 9) begin
            tb_sda_drive <= 1'b0;

        end else if (bit_count >= 10 && bit_count <= 17) begin
            tb_sda_drive <= (rw == 1) ? slave_tx_data[17 - bit_count] : 1'bz;

        end else if (bit_count == 18) begin
            tb_sda_drive <= 1'bz;
            bit_count = 9;
        end
    end
end
endmodule


