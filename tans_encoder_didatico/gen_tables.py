"""
Gerador de tabelas pré-computadas (.txt) e modelo de referência (Python)
para o Encoder tANS em escala didática (L = 16, R = 4, 3 símbolos).

Baseado nas referências do projeto:
- tANS_py / tANS-master (C) / Duda (2014)
- Spread rápido com passo constante (step = 5, compatível com L=16)
"""

from pathlib import Path
import math


def fast_spread(L: int, L_s: list[int], step: int = 5) -> list[int]:
    """Espalha os símbolos na tabela de tamanho L usando passo coprimo com L."""
    if math.gcd(step, L) != 1:
        raise ValueError(f"step={step} deve ser coprimo com L={L}")
    spread = [0] * L
    pos = 0
    for s, freq in enumerate(L_s):
        for _ in range(freq):
            spread[pos] = s
            pos = (pos + step) % L
    return spread


def build_tans_tables(L: int, L_s: list[int], step: int = 5):
    """
    Constrói as tabelas do Encoder e do Decoder tANS.

    Para o hardware do Encoder, precisamos apenas de 3 tabelas:
      1. sym_nb[s]   = (k[s] << (R + 1)) - (L_s[s] << k[s])
      2. sym_off[s]  = (sum(L_s[:s]) - L_s[s]) % L
      3. enc_table[i] em [L, 2L - 1], para i in [0, L - 1]
    """
    assert L > 0 and (L & (L - 1)) == 0, "L deve ser potência de 2"
    assert sum(L_s) == L, "A soma das frequências L_s deve ser igual a L"

    R = int(math.log2(L))
    r = R + 1
    n_sym = len(L_s)
    spread = fast_spread(L, L_s, step=step)

    # Tabelas do Encoder
    k = [R - int(math.floor(math.log2(f))) for f in L_s]
    sym_nb = [(k[s] << r) - (L_s[s] << k[s]) for s in range(n_sym)]
    # Equivalente sem sinal de start[s] = sum(L_s[:s]) - L_s[s]
    sym_off = [(sum(L_s[:s]) - L_s[s]) % L for s in range(n_sym)]

    enc_table = [0] * L
    next_occ = list(L_s)
    for i in range(L):
        s = spread[i]
        idx = (sym_off[s] + next_occ[s]) % L
        enc_table[idx] = L + i
        next_occ[s] += 1

    # Tabela do Decoder (usada no modelo Python para validação round-trip)
    dec_table = []
    next_occ_dec = list(L_s)
    for X in range(L):
        s = spread[X]
        x_tmp = next_occ_dec[s]
        next_occ_dec[s] += 1
        nb = R - int(math.floor(math.log2(x_tmp)))
        new_x = (x_tmp << nb) - L
        dec_table.append((s, nb, new_x))

    return {
        "L": L,
        "R": R,
        "r": r,
        "L_s": L_s,
        "spread": spread,
        "k": k,
        "sym_nb": sym_nb,
        "sym_off": sym_off,
        "enc_table": enc_table,
        "dec_table": dec_table,
    }


def encode_reference(msg: list[int], tables: dict, init_state: int):
    """Modelo de referência do Encoder tANS (1 símbolo por passo)."""
    L = tables["L"]
    r = tables["r"]
    sym_nb = tables["sym_nb"]
    sym_off = tables["sym_off"]
    enc_table = tables["enc_table"]

    state = init_state
    steps = []
    bitstream = []

    for s in msg:
        nb_bits = (state + sym_nb[s]) >> r
        out_bits = state & ((1 << nb_bits) - 1) if nb_bits > 0 else 0
        x_tmp = state >> nb_bits
        idx = (sym_off[s] + x_tmp) & (L - 1)
        next_state = enc_table[idx]

        # Armazena os bits gerados (MSB-first dentro dos nb_bits extraídos)
        for b in range(nb_bits - 1, -1, -1):
            bitstream.append((out_bits >> b) & 1)

        steps.append({
            "sym": s,
            "state_in": state,
            "nb_bits": nb_bits,
            "out_bits": out_bits,
            "x_tmp": x_tmp,
            "idx": idx,
            "next_state": next_state,
        })
        state = next_state

    return steps, bitstream, state


def decode_reference(bitstream: list[int], final_state: int, n_symbols: int, tables: dict):
    """Modelo de referência do Decoder tANS para validar round-trip."""
    L = tables["L"]
    dec_table = tables["dec_table"]

    state_idx = final_state - L
    bits = list(bitstream)
    decoded_rev = []

    for _ in range(n_symbols):
        s, nb, new_x = dec_table[state_idx]
        if nb > 0:
            chunk = bits[-nb:]
            bits = bits[:-nb]
            val = 0
            for b in chunk:
                val = (val << 1) | b
        else:
            val = 0
        decoded_rev.append(s)
        state_idx = new_x + val

    decoded = list(reversed(decoded_rev))
    return decoded, state_idx + L, bits


def pack_bits_msb_bytes(bitstream: list[int]) -> tuple[list[int], int]:
    """Empacota uma lista de bits MSB-first em bytes (completa com zeros no LSB do último byte)."""
    padded = list(bitstream)
    rem = len(padded) % 8
    valid_last = 8 if rem == 0 else rem
    if rem != 0:
        padded.extend([0] * (8 - rem))
    out_bytes = []
    for i in range(0, len(padded), 8):
        val = 0
        for b in padded[i : i + 8]:
            val = (val << 1) | b
        out_bytes.append(val)
    return out_bytes, valid_last


def main():
    out_dir = Path(__file__).resolve().parent

    # Escala didática: L = 16 estados (R = 4 bits), 3 símbolos (a=0, b=1, c=2)
    # Frequências da referência PNG: L_0=3, L_1=8, L_2=5 (soma = 16)
    L = 16
    L_s = [3, 8, 5]
    tables = build_tans_tables(L, L_s, step=5)

    # Preenche tabela de símbolos até 4 entradas (SYM_WIDTH = 2 bits -> 0..3)
    sym_nb_padded = tables["sym_nb"] + [0]
    sym_off_padded = tables["sym_off"] + [0]

    # Escreve os arquivos .txt para o banco de registradores ($readmemh)
    (out_dir / "lut_sym_nb.txt").write_text(
        "\n".join(f"{v:02x}" for v in sym_nb_padded) + "\n", encoding="utf-8"
    )
    (out_dir / "lut_sym_off.txt").write_text(
        "\n".join(f"{v:01x}" for v in sym_off_padded) + "\n", encoding="utf-8"
    )
    (out_dir / "lut_enc_table.txt").write_text(
        "\n".join(f"{v:02x}" for v in tables["enc_table"]) + "\n", encoding="utf-8"
    )

    # Mensagem de teste didática (12 símbolos no alfabeto {0, 1, 2})
    test_msg = [0, 1, 2, 1, 0, 2, 1, 1, 2, 0, 1, 2]
    init_state = 16  # Estado inicial L = 16 (0x10)

    steps, bitstream, final_state = encode_reference(test_msg, tables, init_state)
    decoded, rec_init, rem_bits = decode_reference(
        bitstream, final_state, len(test_msg), tables
    )
    assert decoded == test_msg, f"Erro round-trip: {decoded} != {test_msg}"
    assert rec_init == init_state, f"Estado inicial divergente: {rec_init} != {init_state}"
    assert len(rem_bits) == 0, f"Sobraram bits: {rem_bits}"

    packed_bytes, _ = pack_bits_msb_bytes(bitstream)

    # Grava vetores de teste para o testbench em Verilog
    # Formato de test_vectors.txt: cada linha = sym(1 hex) nb_bits(1 hex) out_bits(1 hex) next_state(2 hex)
    vec_lines = [
        f"{st['sym']:01x}_{st['nb_bits']:01x}_{st['out_bits']:01x}_{st['next_state']:02x}"
        for st in steps
    ]
    (out_dir / "test_vectors.txt").write_text("\n".join(vec_lines) + "\n", encoding="utf-8")
    (out_dir / "expected_bytes.txt").write_text(
        "\n".join(f"{b:02x}" for b in packed_bytes) + "\n", encoding="utf-8"
    )

    print("=== Tabelas Geradas (L=16, L_s=[3,8,5], step=5) ===")
    print("spread   :", tables["spread"])
    print("k        :", tables["k"])
    print("sym_nb   :", tables["sym_nb"])
    print("sym_off  :", tables["sym_off"])
    print("enc_table:", tables["enc_table"])
    print("\n=== Traço de Codificação ===")
    for i, st in enumerate(steps):
        print(
            f"passo {i:2d}: sym={st['sym']} state_in={st['state_in']:2d} -> "
            f"nbBits={st['nb_bits']} out_bits={st['out_bits']:d} ({st['out_bits']:0{st['nb_bits']}b}) "
            f"x_tmp={st['x_tmp']:2d} idx={st['idx']:2d} -> next_state={st['next_state']:2d}"
        )
    print(f"\nEstado final : {final_state} (0x{final_state:02x})")
    print(f"Total de bits: {len(bitstream)} -> {''.join(str(b) for b in bitstream)}")
    print(f"Bytes (MSB)  : {[f'0x{b:02x}' for b in packed_bytes]}")
    print("Round-trip Python decode OK!")


if __name__ == "__main__":
    main()
