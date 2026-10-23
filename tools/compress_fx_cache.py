"""Losslessly store frame geometry as independently compressed, deduplicated blocks."""
from pathlib import Path
import hashlib
import json
import struct
import zlib


def compress_folder(folder: Path):
    meta_path = folder / 'frames.json'
    meta = json.loads(meta_path.read_text('utf-8'))
    source = folder / 'frames.bin'
    target = folder / 'frames.fxc'
    version = int(meta['binary_version'])
    assert version in (2, 3, 4)
    stride = {2: 48, 3: 64, 4: 96}[version]
    header_size = 12 if version == 4 else 16
    blocks, frame_blocks, seen = [], [], {}
    raw_size = source.stat().st_size
    with source.open('rb') as src, source.open('rb') as verify, target.open('wb') as dst:
        for frame in meta['frames']:
            src.seek(frame['offset'])
            count, = struct.unpack('<I', src.read(4))
            ids = []
            for _ in range(count):
                start = src.tell()
                header = src.read(header_size)
                group, nv, ni = struct.unpack_from('<III', header)
                body = src.read(nv * stride + ni * 4)
                assert len(body) == nv * stride + ni * 4
                digest = hashlib.sha256(header + body).digest()
                if digest in seen:
                    block_id, original_offset = seen[digest]
                    verify.seek(original_offset)
                    assert verify.read(header_size + len(body)) == header + body
                    blocks[block_id][4] += 1
                else:
                    compressed = zlib.compress(body, 1)
                    codec = 1 if len(compressed) < len(body) else 0
                    payload = compressed if codec else body
                    # offset, stored bytes, raw body bytes, exact header, uses, codec
                    block_id = len(blocks)
                    blocks.append([dst.tell(), len(payload), len(body), header.hex(), 1, codec])
                    dst.write(payload)
                    seen[digest] = (block_id, start)
                ids.append(block_id)
            assert src.tell() == int(frame['offset']) + int(frame['bytes'])
            frame_blocks.append(ids)
    # Every group has already been verified on decode; keep author/raw caches intact.
    with source.open('rb') as src, target.open('rb') as packed:
        for frame, ids in zip(meta['frames'], frame_blocks):
            src.seek(frame['offset'])
            expected = src.read(frame['bytes'])
            restored = bytearray(struct.pack('<I', len(ids)))
            for block_id in ids:
                offset, stored, raw, header, _, codec = blocks[block_id]
                packed.seek(offset)
                payload = packed.read(stored)
                body = zlib.decompress(payload) if codec else payload
                assert len(body) == raw
                restored.extend(bytes.fromhex(header))
                restored.extend(body)
            assert restored == expected
    with source.open('rb') as original:
        raw_hash = hashlib.file_digest(original, 'sha256').hexdigest()
    meta['storage'] = {'format': 'group_blocks_v1', 'file': 'frames.fxc',
                       'raw_bytes': raw_size, 'raw_sha256': raw_hash,
                       'blocks': blocks, 'frames': frame_blocks}
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    # This exact generated copy is replaced; source author caches remain untouched.
    source.unlink()
    print(f'FX_COMPRESSED {folder.name or "skill1"}: {raw_size:,} -> {target.stat().st_size:,} bytes; {len(blocks)} unique blocks; exact frame reconstruction PASS')
    return {'folder': folder.as_posix(), 'raw_bytes': raw_size,
            'stored_bytes': target.stat().st_size, 'blocks': len(blocks), 'frames': len(frame_blocks)}
