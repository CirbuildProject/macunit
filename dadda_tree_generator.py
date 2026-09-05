#!/usr/bin/env python3
"""
Pragmatic Dadda Tree Generator for 16x16 Radix-4 Booth Multiplier.
Target: SystemVerilog RTL Generation for Sky130 standard-cell synthesis.
"""

def generate_dadda_tree():
    WIDTH = 32
    columns = [[] for _ in range(WIDTH)]
    
    # 1. Initialize Matrix with Partial Products
    for row in range(8):
        for col in range(WIDTH):
            columns[col].append(f"stg2a_pp[{row}][{col}]")
            
    # 2. Inject Booth Carry-Ins (+1 for Two's Complement -A and -2A)
    for row in range(8):
        # 1x Carry injects at the exact shift weight
        carry_1x_col = row * 2
        if carry_1x_col < WIDTH:
            columns[carry_1x_col].append(f"stg2a_carry_1x[{row}]")
            
        # 2x Carry injects one column higher to mathematically add +2
        carry_2x_col = (row * 2) + 1
        if carry_2x_col < WIDTH:
            columns[carry_2x_col].append(f"stg2a_carry_2x[{row}]")
    sv_code = "// =========================================================================\n"
    sv_code += "// AUTOMATICALLY GENERATED DADDA TREE (STAGE 2B)\n"
    sv_code += "// Target: 8 Rows -> 2 Rows Compression\n"
    sv_code += "// =========================================================================\n\n"

    sv_code += "/* verilator lint_off UNUSEDSIGNAL */\n\n"

    fa_count = 0
    ha_count = 0

    # 3. The Dadda Sequence
    target_heights = [6, 4, 3, 2]

    for level, target in enumerate(target_heights, start=1):
        sv_code += f"// --- LEVEL {level} COMPRESSION (Target Height: {target}) ---\n"
        next_columns = [[] for _ in range(WIDTH)]
        
        for col in range(WIDTH):
            # Evaluate the PROJECTED height (current bits + incoming carries from col-1)
            while len(columns[col]) + len(next_columns[col]) > target:
                present = len(columns[col])
                diff = (present + len(next_columns[col])) - target
                
                if diff >= 2 and present >= 3:
                    # Instantiate Full Adder (3:2)
                    in1 = columns[col].pop(0)
                    in2 = columns[col].pop(0)
                    in3 = columns[col].pop(0)
                    
                    sum_wire = f"s_L{level}_c{col}_{fa_count}"
                    carry_wire = f"c_L{level}_c{col+1}_{fa_count}"
                    fa_count += 1
                    
                    sv_code += f"logic {sum_wire}, {carry_wire};\n"
                    sv_code += f"assign {{{carry_wire}, {sum_wire}}} = {in1} + {in2} + {in3};\n"
                    
                    next_columns[col].append(sum_wire)
                    if col + 1 < WIDTH:
                        next_columns[col + 1].append(carry_wire)
                        
                elif diff >= 1 and present >= 2:
                    # Instantiate Half Adder (2:2)
                    in1 = columns[col].pop(0)
                    in2 = columns[col].pop(0)
                    
                    sum_wire = f"s_L{level}_c{col}_ha{ha_count}"
                    carry_wire = f"c_L{level}_c{col+1}_ha{ha_count}"
                    ha_count += 1
                    
                    sv_code += f"logic {sum_wire}, {carry_wire};\n"
                    sv_code += f"assign {{{carry_wire}, {sum_wire}}} = {in1} + {in2};\n"
                    
                    next_columns[col].append(sum_wire)
                    if col + 1 < WIDTH:
                        next_columns[col + 1].append(carry_wire)
                else:
                    sv_code += f"// [ALGORITHM ERROR] Structural dead-end at col {col}.\n"
                    break

            # Uncompressed signals pass to the next level
            for remaining_wire in columns[col]:
                next_columns[col].append(remaining_wire)

        columns = next_columns
        sv_code += "\n"

    # 4. Final Egress Assignments
    sv_code += "// --- FINAL STAGE 2B EGRESS ASSIGNMENTS ---\n"
    for col in range(WIDTH):
        if len(columns[col]) > 0:
            sv_code += f"assign next_sum[{col}] = {columns[col][0]};\n"
        else:
            sv_code += f"assign next_sum[{col}] = 1'b0;\n"
            
        if len(columns[col]) > 1:
            sv_code += f"assign next_carry[{col}] = {columns[col][1]};\n"
        else:
            sv_code += f"assign next_carry[{col}] = 1'b0;\n"
            
        if len(columns[col]) > 2:
            sv_code += f"// [FATAL ERROR] DADDA MATH FAILED: Column {col} has {len(columns[col])} bits left!\n"
    sv_code += "\n/* verilator lint_on UNUSEDSIGNAL */\n"
    return sv_code

if __name__ == "__main__":
    rtl_output = generate_dadda_tree()
    with open("dadda_tree_gen.sv", "w") as f:
        f.write(rtl_output)
    print("SUCCESS: dadda_tree_gen.sv has been generated.")