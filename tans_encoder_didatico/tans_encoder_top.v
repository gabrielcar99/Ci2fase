`timescale 1ns/1ps

// ============================================================================
// Modulo: tans_encoder_top
// Descricao: Modulo topo do Encoder tANS em escala didatica.
//            Integra:
//              1) tans_table_bank   (banco de registradores via .txt)
//              2) tans_encoder_core (1 simbolo/ciclo, sem mult/div)
//              3) tans_bit_packer   (empacotamento em bytes + flush)
// Padrao: Verilog-2001 sintetizavel
// ============================================================================

module tans_encoder_top #(
    parameter L                  = 16,
    parameter R                  = 4,
    parameter SYM_WIDTH          = 2,
    parameter NUM_SYMS           = 4,
    parameter NB_WIDTH           = 3,
    parameter NB_PARAM_W         = 8,
    parameter LUT_SYM_NB_FILE    = "lut_sym_nb.txt",
    parameter LUT_SYM_OFF_FILE   = "lut_sym_off.txt",
    parameter LUT_ENC_TABLE_FILE = "lut_enc_table.txt"
) (
    input  wire                  clk,
    input  wire                  rst_n,

    // Controle do bloco
    input  wire                  init_en,
    input  wire [R:0]            init_state,

    // Entrada de simbolos
    input  wire                  sym_valid,
    input  wire [SYM_WIDTH-1:0]  sym_in,
    input  wire                  sym_last,

    // Porta de programacao opcional do banco de registradores
    input  wire                  tbl_wr_en,
    input  wire [1:0]            tbl_wr_sel,
    input  wire [R-1:0]          tbl_wr_addr,
    input  wire [NB_PARAM_W-1:0] tbl_wr_data,

    // Saidas de depuracao por passo (bits variaveis diretos do nucleo)
    output wire                  step_valid,
    output wire [R-1:0]          step_bits,
    output wire [NB_WIDTH-1:0]   step_nbits,
    output wire                  step_last,

    // Saida empacotada em bytes
    output wire                  byte_valid,
    output wire [7:0]            byte_out,
    output wire                  byte_last,
    output wire [3:0]            byte_last_bits,

    // Estado final e sinal de conclusao do nucleo
    output wire [R:0]            final_state,
    output wire                  core_done
);

    wire [SYM_WIDTH-1:0]  lut_sym_addr;
    wire [NB_PARAM_W-1:0] lut_sym_nb;
    wire [R-1:0]          lut_sym_off;
    wire [R-1:0]          lut_enc_addr;
    wire [R:0]            lut_enc_data;

    tans_table_bank #(
        .L                 (L),
        .R                 (R),
        .SYM_WIDTH         (SYM_WIDTH),
        .NUM_SYMS          (NUM_SYMS),
        .NB_PARAM_W        (NB_PARAM_W),
        .LUT_SYM_NB_FILE   (LUT_SYM_NB_FILE),
        .LUT_SYM_OFF_FILE  (LUT_SYM_OFF_FILE),
        .LUT_ENC_TABLE_FILE(LUT_ENC_TABLE_FILE)
    ) u_table_bank (
        .clk           (clk),
        .sym_addr      (lut_sym_addr),
        .sym_nb_data   (lut_sym_nb),
        .sym_off_data  (lut_sym_off),
        .enc_addr      (lut_enc_addr),
        .enc_table_data(lut_enc_data),
        .wr_en         (tbl_wr_en),
        .wr_sel        (tbl_wr_sel),
        .wr_addr       (tbl_wr_addr),
        .wr_data       (tbl_wr_data)
    );

    tans_encoder_core #(
        .L         (L),
        .R         (R),
        .SYM_WIDTH (SYM_WIDTH),
        .NB_WIDTH  (NB_WIDTH),
        .NB_PARAM_W(NB_PARAM_W)
    ) u_encoder_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .init_en     (init_en),
        .init_state  (init_state),
        .sym_valid   (sym_valid),
        .sym_in      (sym_in),
        .sym_last    (sym_last),
        .lut_sym_addr(lut_sym_addr),
        .lut_sym_nb  (lut_sym_nb),
        .lut_sym_off (lut_sym_off),
        .lut_enc_addr(lut_enc_addr),
        .lut_enc_data(lut_enc_data),
        .out_valid   (step_valid),
        .out_bits    (step_bits),
        .out_nbits   (step_nbits),
        .out_last    (step_last),
        .state_reg   (final_state),
        .done        (core_done)
    );

    tans_bit_packer #(
        .R       (R),
        .NB_WIDTH(NB_WIDTH)
    ) u_bit_packer (
        .clk           (clk),
        .rst_n         (rst_n),
        .clear         (init_en),
        .in_valid      (step_valid),
        .in_bits       (step_bits),
        .in_nbits      (step_nbits),
        .in_last       (step_last),
        .byte_valid    (byte_valid),
        .byte_out      (byte_out),
        .byte_last     (byte_last),
        .byte_last_bits(byte_last_bits)
    );

endmodule
