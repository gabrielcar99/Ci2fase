`timescale 1ns/1ps

// ============================================================================
// Modulo: tans_table_bank
// Descricao: Banco de registradores para o Encoder tANS com tabelas
//            pre-computadas carregadas a partir de arquivos .txt ($readmemh).
//            Possui leitura combinacional (1 simbolo/ciclo) e porta de escrita
//            sincrona opcional para atualizacao dinamica futura.
// Padrao: Verilog-2001 sintetizavel
// ============================================================================

module tans_table_bank #(
    parameter L                  = 16,
    parameter R                  = 4,
    parameter SYM_WIDTH          = 2,
    parameter NUM_SYMS           = 4,
    parameter NB_PARAM_W         = 8,
    parameter LUT_SYM_NB_FILE    = "lut_sym_nb.txt",
    parameter LUT_SYM_OFF_FILE   = "lut_sym_off.txt",
    parameter LUT_ENC_TABLE_FILE = "lut_enc_table.txt"
) (
    input  wire                  clk,

    // Porta de leitura combinacional do Encoder
    input  wire [SYM_WIDTH-1:0]  sym_addr,
    output wire [NB_PARAM_W-1:0] sym_nb_data,
    output wire [R-1:0]          sym_off_data,

    input  wire [R-1:0]          enc_addr,
    output wire [R:0]            enc_table_data,

    // Porta de escrita sincrona (opcional, para reconfiguracao em runtime)
    input  wire                  wr_en,
    input  wire [1:0]            wr_sel,   // 00: sym_nb, 01: sym_off, 10: enc_table
    input  wire [R-1:0]          wr_addr,
    input  wire [NB_PARAM_W-1:0] wr_data
);

    // Bancos de registradores das 3 tabelas do Encoder
    reg [NB_PARAM_W-1:0] sym_nb_regs    [0:NUM_SYMS-1];
    reg [R-1:0]          sym_off_regs   [0:NUM_SYMS-1];
    reg [R:0]            enc_table_regs [0:L-1];

    // Carga inicial a partir dos arquivos .txt pre-computados
    initial begin
        $readmemh(LUT_SYM_NB_FILE,    sym_nb_regs);
        $readmemh(LUT_SYM_OFF_FILE,   sym_off_regs);
        $readmemh(LUT_ENC_TABLE_FILE, enc_table_regs);
    end

    // Leituras combinacionais (0 ciclos de latencia de acesso)
    assign sym_nb_data    = sym_nb_regs[sym_addr];
    assign sym_off_data   = sym_off_regs[sym_addr];
    assign enc_table_data = enc_table_regs[enc_addr];

    // Escrita sincrona opcional no banco de registradores
    always @(posedge clk) begin
        if (wr_en) begin
            case (wr_sel)
                2'b00: sym_nb_regs[wr_addr[SYM_WIDTH-1:0]]  <= wr_data;
                2'b01: sym_off_regs[wr_addr[SYM_WIDTH-1:0]] <= wr_data[R-1:0];
                2'b10: enc_table_regs[wr_addr]              <= wr_data[R:0];
                default: ;
            endcase
        end
    end

endmodule
