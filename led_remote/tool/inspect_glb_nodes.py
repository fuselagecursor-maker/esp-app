"""Print GLB node/mesh names for prop discovery."""
import json
import struct
import sys
from pathlib import Path


def inspect(path: Path) -> None:
    data = path.read_bytes()
    json_len = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + json_len])
    nodes = gltf.get("nodes", [])
    meshes = gltf.get("meshes", [])
    print(f"{path.name}: {len(nodes)} nodes, {len(meshes)} meshes")
    for i, n in enumerate(nodes):
        name = n.get("name", f"node_{i}")
        print(
            f"  node[{i}] {name!r} mesh={n.get('mesh')} "
            f"children={n.get('children', [])}"
        )
    print("--- meshes ---")
    for i, m in enumerate(meshes):
        print(f"  mesh[{i}] {m.get('name', '?')!r}")


if __name__ == "__main__":
    p = Path(sys.argv[1] if len(sys.argv) > 1 else r"d:\esp\led_remote\assets\models\dji_tello.glb")
    inspect(p)
