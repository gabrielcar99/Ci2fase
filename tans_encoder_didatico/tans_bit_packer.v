`timescale 1ns/1ps

// ============================================================================
// Modulo: tans_bit_packer
// Descricao: Empacotador de bitstream de largura variavel (0..R bits por ciclo)
//            para palavras de 8 bits (bytes), mantendo ordem MSB-first dentro
//            de cada palavra extraida e realizando flush ao final (in_last).
// Padrao: Verilog-2001 sintetizavel (valido para R <= 8)
// ============================================================================

module tans_bit_packer #(
    parameter R        = 4,
    parameter NB_WIDTH = 3
) (
    input  wire                clk,
    input  wire                rst_n,
    input  wire                clear,

    input  wire                in_valid,
    input  wire [R-1:0]        in_bits,
    input  wire [NB_WIDTH-1:0] in_nbits,
    input  wire                in_last,

    output reg                 byte_valid,
    output reg  [7:0]          byte_out,
    output reg                 byte_last,
    output reg  [3:0]          byte_last_bits // Qtd de bits validos no ultimo byte (1..8, ou 0 se vazio)
);

    localparam BUF_W = 16;

    reg [BUF_W-1:0] bit_buf;
    reg [3:0]       bit_cnt;        // Sempre em 0..7 entre ciclos normais
    reg             flush_pending;  // Caso raro onde sobram bits apos emitir 1 byte no in_last

    // Combinacional para o ciclo atual
    wire [BUF_W-1:0] in_bits_ext = {{(BUF_W-R){1'b0}}, in_bits};
    wire [BUF_W-1:0] shifted_buf = (bit_buf << in_nbits) | in_bits_ext;
    wire [4:0]       total_bits  = {1'b0, bit_cnt} + {{(5-NB_WIDTH){1'b0}}, in_nbits};

    wire [4:0]       rem_after_byte = total_bits - 5'd8;
    wire [BUF_W-1:0] rem_mask       = ({{(BUF_W-1){1'b0}}, 1'b1} << rem_after_byte[3:0]) - {{(BUF_W-1){1'b0}}, 1'b1};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_buf        <= {BUF_W{1'b0}};
            bit_cnt        <= 4'd0;
            flush_pending  <= 1'b0;
            byte_valid     <= 1'b0;
            byte_out       <= 8'd0;
            byte_last      <= 1'b0;
            byte_last_bits <= 4'd0;
        end else if (clear) begin
            bit_buf        <= {BUF_W{1'b0}};
            bit_cnt        <= 4'd0;
            flush_pending  <= 1'b0;
            byte_valid     <= 1'b0;
            byte_out       <= 8'd0;
            byte_last      <= 1'b0;
            byte_last_bits <= 4'd0;
        end else begin
            byte_valid     <= 1'b0;
            byte_last      <= 1'b0;
            byte_last_bits <= 4'd0;

            if (flush_pending) begin
                // Emite os bits residuais (1..7 bits) alinhados ao MSB do byte
                byte_valid     <= 1'b1;
                byte_out       <= bit_buf[7:0] << (4'd8 - bit_cnt);
                byte_last      <= 1'b1;
                byte_last_bits <= bit_cnt;
                bit_buf        <= {BUF_W{1'b0}};
                bit_cnt        <= 4'd0;
                flush_pending  <= 1'b0;
            end else if (in_valid) begin
                if (total_bits >= 5'd8) begin
                    // Emite 1 byte completo (8 bits mais antigos)
                    byte_valid <= 1'b1;
                    byte_out   <= shifted_buf >> rem_after_byte[3:0];

                    if (in_last) begin
                        if (rem_after_byte == 5'd0) begin
                            byte_last      <= 1'b1;
                            byte_last_bits <= 4'd8;
                            bit_buf        <= {BUF_W{1'b0}};
                            bit_cnt        <= 4'd0;
                        end else begin
                            // Ainda sobraram 1..7 bits para emitir no proximo ciclo
                            bit_buf       <= shifted_buf & rem_mask;
                            bit_cnt       <= rem_after_byte[3:0];
                            flush_pending <= 1'b1;
                        end
                    end else begin
                        bit_buf <= shifted_buf & rem_mask;
                        bit_cnt <= rem_after_byte[3:0];
                    end
                end else begin
                    // Menos de 8 bits acumulados
                    if (in_last) begin
                        if (total_bits > 5'd0) begin
                            byte_valid     <= 1'b1;
                            byte_out       <= shifted_buf[7:0] << (4'd8 - total_bits[3:0]);
                            byte_last      <= 1'b1;
                            byte_last_bits <= total_bits[3:0];
                        end else begin
                            byte_valid     <= 1'b0;
                            byte_last      <= 1'b1;
                            byte_last_bits <= 4'd0;
                        end
                        bit_buf <= {BUF_W{1'b0}};
                        bit_cnt <= 4'd0;
                    end else begin
                        bit_buf <= shifted_buf;
                        bit_cnt <= total_bits[3:0];
                    end
                end
            end
        end
    end

endmodule
