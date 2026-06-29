import os
import json
import glob
import re
import xml.etree.ElementTree as ET
import time
from collections import defaultdict

# Setup dynamic paths so it works seamlessly on macOS or Windows
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA_JSON_PATH = os.path.join(BASE_DIR, "assets", "schema_data.json")

SOURCE_DIR = "/Users/myFlo_unipaas/source"
if not os.path.exists(SOURCE_DIR):
    SOURCE_DIR = r"c:\Data\MV101Apps\MyFlo\source"

def load_schema():
    print(f"Loading schema data from {SCHEMA_JSON_PATH}...")
    with open(SCHEMA_JSON_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
        if content.startswith('\ufeff'):
            content = content[1:]
        return json.loads(content)

def main():
    start_time = time.time()
    
    schema_data = load_schema()
    tables = schema_data.get('tables', [])
    
    table_id_map = {}
    col_id_map = {}
    
    for t in tables:
        t_obj = str(t.get('id', ''))
        t_name = t.get('name', '')
        table_id_map[t_obj] = t_name
        
        for c in t.get('columns', []):
            c_id = str(c.get('id', ''))
            c_name = c.get('name', '')
            col_id_map[f"{t_obj}.{c_id}"] = c_name
            
    print(f"Loaded {len(tables)} tables from schema.")

    prg_files = glob.glob(os.path.join(SOURCE_DIR, "Prg_*.xml"))
    print(f"Found {len(prg_files)} program files to scan.")

    rel_programs = defaultdict(set)
    exact_exp_re = re.compile(r'^\{0,(\d+)\}$')

    programs_metadata = []

    count = 0
    for prg_file in prg_files:
        count += 1
        if count % 500 == 0:
            print(f"Processed {count} / {len(prg_files)} files...")
            
        try:
            tree = ET.parse(prg_file)
            root = tree.getroot()
        except Exception as e:
            print(f"Error parsing {prg_file}: {e}")
            continue
            
        program_name = os.path.basename(prg_file)
        prog_id = ""
        match_id = re.search(r'Prg_(\d+)\.xml', os.path.basename(prg_file))
        if match_id:
            prog_id = match_id.group(1)

        first_task = root.find(".//Task")
        if first_task is not None:
            prog_header = first_task.find("Header")
            if prog_header is not None:
                if prog_header.get("Description"):
                    program_name = prog_header.get("Description")
                if prog_header.get("id") and not prog_id:
                    prog_id = prog_header.get("id")

        # Extract variables and parameters for this program from Resource/Columns
        col_info_map = {}
        for col in root.findall(".//Resource/Columns/Column"):
            c_id = col.get("id")
            c_name = col.get("name", f"Var_{c_id}")
            model_node = col.find("PropertyList/Model")
            c_type = model_node.get("attr_obj", "ALPHA") if model_node is not None else "ALPHA"
            col_info_map[c_id] = {"name": c_name, "type": c_type.replace("FIELD_", "")}

        params_map = {}
        for select_node in root.findall(".//TaskLogic//Select"):
            f_id = select_node.get("FieldID")
            c_val_node = select_node.find("Column")
            c_val = c_val_node.get("val") if c_val_node is not None else None
            t_node = select_node.find("Type")
            t_val = t_node.get("val") if t_node is not None else ""
            p_node = select_node.find("IsParameter")
            is_param = (p_node.get("val") == "Y") if p_node is not None else False

            if t_val == "V" and c_val in col_info_map and f_id not in params_map:
                info = col_info_map[c_val]
                params_map[f_id] = {
                    "fieldId": f_id,
                    "colId": c_val,
                    "name": info["name"],
                    "type": info["type"],
                    "isParameter": is_param
                }

        # Also add any columns from Resource/Columns that weren't found in Select nodes
        for c_id, info in col_info_map.items():
            if not any(p["colId"] == c_id for p in params_map.values()):
                params_map[f"col_{c_id}"] = {
                    "fieldId": c_id,
                    "colId": c_id,
                    "name": info["name"],
                    "type": info["type"],
                    "isParameter": False
                }

        sorted_params = sorted(params_map.values(), key=lambda x: int(re.sub(r'\D', '', x["fieldId"])) if re.sub(r'\D', '', x["fieldId"]).isdigit() else 999)

        has_tables = False
        try:
            with open(prg_file, 'r', encoding='utf-8', errors='ignore') as pf:
                p_content = pf.read()
            db_m = re.findall(r'<(?:DB|DataObject)\s+[^>]*?obj=\"([^\"]+)\"', p_content)
            has_valid = any(m != '0' and m != '' for m in db_m)
            has_lnk = '<LNK ' in p_content
            has_tables = has_valid or has_lnk
        except Exception:
            has_tables = True

        programs_metadata.append({
            "id": prog_id,
            "filename": os.path.basename(prg_file),
            "name": program_name,
            "parameters": sorted_params,
            "hasTables": has_tables
        })

        # Relationship scanning (original logic preserved)
        for task in root.findall(".//Task"):
            main_table_obj = None
            info_db = task.find("Information/DB")
            if info_db is not None and info_db.get("obj"):
                main_table_obj = info_db.get("obj")
                
            if not main_table_obj:
                res_db = task.find("Resource/DB")
                if res_db is not None:
                    db_data_obj = res_db.find("DataObject")
                    if db_data_obj is not None and db_data_obj.get("obj"):
                        main_table_obj = db_data_obj.get("obj")
                    elif res_db.get("obj"):
                        main_table_obj = res_db.get("obj")

            exp_map = {}
            expressions_node = task.find("Expressions")
            if expressions_node is not None:
                exp_index = 1
                for exp in expressions_node.findall("Expression"):
                    syntax_node = exp.find("ExpSyntax")
                    if syntax_node is not None and syntax_node.get("val"):
                        exp_map[str(exp_index)] = syntax_node.get("val")
                    exp_index += 1

            logic_units = task.findall("TaskLogic/LogicUnit")
            field_map = {}
            current_table_obj = main_table_obj
            table_stack = []

            for lu in logic_units:
                logic_lines = lu.find("LogicLines")
                if logic_lines is None:
                    continue
                    
                for logic_line in logic_lines:
                    if logic_line.tag != "LogicLine":
                        continue
                        
                    if len(logic_line) == 0:
                        continue
                    op = logic_line[0]
                    
                    if op.tag == "DATAVIEW_SRC":
                        current_table_obj = main_table_obj
                        table_stack.clear()
                        
                    elif op.tag == "LNK":
                        table_stack.append(current_table_obj)
                        db_node = op.find("DB")
                        if db_node is not None:
                            if db_node.get("obj"):
                                current_table_obj = db_node.get("obj")
                            else:
                                data_obj = db_node.find("DataObject")
                                if data_obj is not None and data_obj.get("obj"):
                                    current_table_obj = data_obj.get("obj")
                                    
                    elif op.tag == "END_LINK":
                        if table_stack:
                            current_table_obj = table_stack.pop()
                        else:
                            current_table_obj = main_table_obj
                            
                    elif op.tag == "Select":
                        field_id = op.get("FieldID")
                        col_node = op.find("Column")
                        col_id = col_node.get("val") if col_node is not None else None
                        type_node = op.find("Type")
                        field_type = type_node.get("val") if type_node is not None else "U"
                        is_param_node = op.find("IsParameter")
                        is_param = is_param_node.get("val") if is_param_node is not None else "N"
                        
                        is_real_column = (field_type == "R" and is_param != "Y")
                        
                        if field_id and col_id and current_table_obj and is_real_column:
                            field_map[field_id] = {
                                "table": current_table_obj,
                                "col": col_id
                            }
                            
                        locate_node = op.find("Locate")
                        if locate_node is not None:
                            max_val = locate_node.get("MAX")
                            min_val = locate_node.get("MIN")
                            exp_id = max_val if max_val else min_val
                            
                            if exp_id and exp_id in exp_map:
                                syntax = exp_map[exp_id]
                                match = exact_exp_re.match(syntax)
                                
                                if match:
                                    src_field_id = match.group(1)
                                    if src_field_id in field_map and is_real_column:
                                        src_info = field_map[src_field_id]
                                        from_table_obj = src_info["table"]
                                        from_col_id = src_info["col"]
                                        to_table_obj = current_table_obj
                                        to_col_id = col_id
                                        
                                        from_table_name = table_id_map.get(from_table_obj)
                                        from_col_name = col_id_map.get(f"{from_table_obj}.{from_col_id}")
                                        to_table_name = table_id_map.get(to_table_obj)
                                        to_col_name = col_id_map.get(f"{to_table_obj}.{to_col_id}")
                                        
                                        if from_table_name and from_col_name and to_table_name and to_col_name:
                                            key = f"{from_table_name}:{from_col_name}:{to_table_name}:{to_col_name}"
                                            rel_programs[key].add(program_name)

    print("\nScan complete!")
    print(f"Extracted metadata for {len(programs_metadata)} programs.")

    existing_rels = {}
    for r in schema_data.get('relationships', []):
        to_col = r.get('toColumn', '')
        key = f"{r.get('fromTable', '')}:{r.get('fromColumn', '')}:{r.get('toTable', '')}:{to_col}"
        existing_rels[key] = r

    for key, prog_set in rel_programs.items():
        prog_list = ", ".join(sorted(list(prog_set)))
        parts = key.split(':')
        if key in existing_rels:
            existing_rels[key]['programs'] = prog_list
        else:
            existing_rels[key] = {
                "fromTable": parts[0],
                "fromColumn": parts[1],
                "toTable": parts[2],
                "toColumn": parts[3],
                "programs": prog_list
            }

    order_map = {}
    headers_path = os.path.join(SOURCE_DIR, "ProgramHeaders.xml")
    if os.path.exists(headers_path):
        try:
            with open(headers_path, 'r', encoding='utf-8') as hf:
                hcontent = hf.read()
            hmatches = re.findall(r'<Program>\s*<Header\s+([^>]+)>', hcontent)
            for idx, hm in enumerate(hmatches):
                id_match = re.search(r'id=\"([^\"]+)\"', hm)
                if id_match and id_match.group(1) not in order_map:
                    order_map[id_match.group(1)] = idx
        except Exception as e:
            print(f"Warning: Could not read ProgramHeaders.xml: {e}")

    programs_metadata.sort(key=lambda x: order_map.get(str(x["id"]), int(x["id"]) if str(x["id"]).isdigit() else 999999))
    schema_data['programs'] = programs_metadata
    schema_data['relationships'] = list(existing_rels.values())

    print(f"Writing updated schema data with {len(programs_metadata)} programs to {SCHEMA_JSON_PATH}...")
    with open(SCHEMA_JSON_PATH, 'w', encoding='utf-8') as f:
        json.dump(schema_data, f, ensure_ascii=False)

    end_time = time.time()
    print(f"\nDone! Total execution time: {end_time - start_time:.2f} seconds")

if __name__ == "__main__":
    main()
