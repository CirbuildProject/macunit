import random

# Hardware Parameters
DATA_W = 16
ACC_W = 40

# Two's Complement Constants
MAX_POS_16 = (1 << (DATA_W - 1)) - 1  # 0x7FFF
MIN_NEG_16 = -(1 << (DATA_W - 1))     # -0x8000

MAX_POS_40 = (1 << (ACC_W - 1)) - 1   # 0x7FFFFFFFFF
MIN_NEG_40 = -(1 << (ACC_W - 1))      # -0x8000000000

def to_twos_comp_hex(val, bits):
    """Converts a Python signed integer to a Two's Complement Hex string."""
    if val < 0:
        val = (1 << bits) + val
    return f"{val:0{bits//4}X}"

def generate_golden_model(num_vectors=100):
    accumulator = 0
    
    with open("stimulus.hex", "w") as f_in, open("expected.hex", "w") as f_out:
        for i in range(num_vectors):
            # 1. Generate Random Inputs
            # Force a few edge cases (max positive/negative) occasionally
            if random.random() < 0.05:
                a = MAX_POS_16
                b = MAX_POS_16
            elif random.random() < 0.10:
                a = MIN_NEG_16
                b = MIN_NEG_16
            else:
                a = random.randint(MIN_NEG_16, MAX_POS_16)
                b = random.randint(MIN_NEG_16, MAX_POS_16)
                
            # 2. Determine Operation (0 = Overwrite, 1 = Accumulate)
            # Start the first operation with a 0 to clear the register
            user_flag = 0 if i == 0 else random.choice([0, 1])

            # 3. Compute 32-bit Product
            product = a * b

            # 4. Compute 40-bit Accumulation & Saturation
            if user_flag == 0:
                accumulator = product
            else:
                raw_sum = accumulator + product
                
                # Hardware-accurate saturation clamping
                if raw_sum > MAX_POS_40:
                    accumulator = MAX_POS_40
                elif raw_sum < MIN_NEG_40:
                    accumulator = MIN_NEG_40
                else:
                    accumulator = raw_sum

            # 5. Format Data for the Testbench
            # s_axis_tdata is {Operand B [15:0], Operand A [15:0]}
            a_hex = to_twos_comp_hex(a, 16)
            b_hex = to_twos_comp_hex(b, 16)
            tdata_hex = f"{b_hex}{a_hex}"
            
            # Write to files
            # Stimulus format: [USER_FLAG] [TDATA_HEX]
            f_in.write(f"{user_flag} {tdata_hex}\n")
            
            # Expected format: [ACCUMULATOR_HEX]
            f_out.write(f"{to_twos_comp_hex(accumulator, 40)}\n")

    print(f"Successfully generated {num_vectors} test vectors.")

if __name__ == "__main__":
    generate_golden_model(250)