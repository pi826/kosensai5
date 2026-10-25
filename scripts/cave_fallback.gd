extends RefCounted
## Fixed, editable emergency blueprint. No random sampling at runtime.
## Rebuild it with tests/regenerate_cave_fallback.gd after changing the cave rules.
static func data() -> Dictionary:
	return {
	"biomes": [{
	"id": 0,
	"name": "翠の水路",
	"rect": Rect2(0, 0, 4096, 3072)
	}, {
	"id": 1,
	"name": "紫晶の回廊",
	"rect": Rect2(4096, 0, 4096, 3072)
	}, {
	"id": 2,
	"name": "灰燼の遺構",
	"rect": Rect2(8192, 0, 4096, 3072)
	}],
	"bounds": Rect2(0, 0, 12288, 3072),
	"breakables": [Rect2(7680, 736, 32, 32), Rect2(4736, 544, 32, 32), Rect2(1120, 2336, 32, 32), Rect2(7232, 1152, 32, 32), Rect2(3520, 1472, 32, 32), Rect2(1344, 2240, 32, 32), Rect2(10688, 2656, 32, 32), Rect2(10624, 2656, 32, 32), Rect2(3616, 1376, 32, 32), Rect2(4832, 544, 32, 32)],
	"chambers": [{
	&"approaches": [Vector2(5696, 2154), Vector2(5728, 2154), Vector2(5760, 2154), Vector2(5856, 2154), Vector2(5936, 2154), Vector2(6016, 2154), Vector2(5472, 2186), Vector2(5536, 2186), Vector2(5600, 2186), Vector2(6176, 2186), Vector2(6224, 2186), Vector2(6272, 2186), Vector2(5856, 2282), Vector2(6336, 2282)],
	&"band": 2,
	&"floor_steps": [],
	"id": 0,
	"kind": "start",
	"rect": Rect2(5408, 1664, 960, 640),
	&"region": 1,
	&"rocks": [],
	&"shelves": [Rect2(5440, 2208, 192, 16), Rect2(6144, 2208, 160, 16), Rect2(5664, 2176, 128, 16), Rect2(5824, 2176, 224, 16)]
	}, {
	&"approaches": [Vector2(2496, 1034), Vector2(2544, 1034), Vector2(2592, 1034), Vector2(2144, 1194), Vector2(2720, 1194), Vector2(3296, 1194)],
	&"band": 1,
	&"floor_steps": [],
	"id": 1,
	"kind": "boss",
	"rect": Rect2(2112, 608, 1216, 608),
	&"region": 0,
	&"rocks": [],
	&"shelves": [Rect2(2464, 1056, 160, 16)]
	}, {
	&"approaches": [Vector2(7232, 2218), Vector2(7312, 2218), Vector2(7392, 2218), Vector2(7232, 2378), Vector2(7312, 2378), Vector2(7392, 2378), Vector2(7232, 2538), Vector2(7312, 2538), Vector2(7392, 2538), Vector2(6464, 2698), Vector2(6992, 2698), Vector2(7520, 2698)],
	&"band": 2,
	&"floor_steps": [],
	"id": 2,
	"kind": "boss",
	"rect": Rect2(6432, 2144, 1120, 576),
	&"region": 1,
	&"rocks": [],
	&"shelves": [Rect2(7200, 2240, 224, 16), Rect2(7200, 2400, 224, 16), Rect2(7200, 2560, 224, 16)]
	}, {
	&"approaches": [Vector2(10752, 554), Vector2(10800, 554), Vector2(10848, 554), Vector2(10880, 714), Vector2(11616, 714)],
	&"band": 0,
	&"floor_steps": [],
	"id": 3,
	"kind": "boss",
	"rect": Rect2(10272, 128, 1376, 608),
	&"region": 2,
	&"rocks": [],
	&"shelves": [Rect2(10720, 576, 160, 16)]
	}, {
	&"approaches": [Vector2(4768, 1706), Vector2(4832, 1706), Vector2(4896, 1706), Vector2(4768, 1866), Vector2(4832, 1866), Vector2(4896, 1866), Vector2(4768, 2026), Vector2(4832, 2026), Vector2(4896, 2026), Vector2(4768, 2186), Vector2(4832, 2186), Vector2(4896, 2186), Vector2(4416, 2314), Vector2(4480, 2314), Vector2(4544, 2314), Vector2(4352, 2346), Vector2(4608, 2346), Vector2(4864, 2346)],
	&"band": 2,
	&"floor_steps": [Rect2(4384, 2336, 192, 32)],
	"id": 4,
	"kind": "normal",
	"rect": Rect2(4256, 1664, 800, 704),
	&"region": 1,
	&"rocks": [Rect2(4448, 1664, 96, 160), Rect2(4288, 1664, 96, 64)],
	&"shelves": [Rect2(4736, 1728, 192, 16), Rect2(4736, 1888, 192, 16), Rect2(4736, 2048, 192, 16), Rect2(4736, 2208, 192, 16)]
	}, {
	&"approaches": [Vector2(4832, 810), Vector2(4912, 810), Vector2(4992, 810), Vector2(4864, 970), Vector2(4928, 970), Vector2(4992, 970), Vector2(4832, 1130), Vector2(4912, 1130), Vector2(4992, 1130), Vector2(4832, 1290), Vector2(4896, 1290), Vector2(4960, 1290), Vector2(5216, 1354), Vector2(5280, 1354), Vector2(5344, 1354), Vector2(4800, 1450), Vector2(5152, 1450), Vector2(5408, 1450), Vector2(5568, 1450)],
	&"band": 1,
	&"floor_steps": [Rect2(5184, 1376, 192, 96)],
	"id": 5,
	"kind": "normal",
	"rect": Rect2(4672, 768, 992, 704),
	&"region": 1,
	&"rocks": [Rect2(5344, 768, 96, 192)],
	&"shelves": [Rect2(4800, 832, 224, 16), Rect2(4832, 992, 192, 16), Rect2(4800, 1152, 224, 16), Rect2(4800, 1312, 192, 16)]
	}, {
	&"approaches": [Vector2(8800, 2026), Vector2(8864, 2026), Vector2(8928, 2026), Vector2(8864, 2186), Vector2(8912, 2186), Vector2(8960, 2186), Vector2(8768, 2346), Vector2(8864, 2346), Vector2(8960, 2346), Vector2(8512, 2378), Vector2(8592, 2378), Vector2(8672, 2378), Vector2(8384, 2506), Vector2(8416, 2506), Vector2(8448, 2506), Vector2(8736, 2506), Vector2(8880, 2506)],
	&"band": 2,
	&"floor_steps": [Rect2(8480, 2400, 224, 128)],
	"id": 6,
	"kind": "normal",
	"rect": Rect2(8352, 2016, 672, 512),
	&"region": 2,
	&"rocks": [Rect2(8544, 2016, 64, 160), Rect2(8384, 2016, 96, 128)],
	&"shelves": [Rect2(8768, 2048, 192, 16), Rect2(8832, 2208, 160, 16), Rect2(8736, 2368, 256, 16)]
	}, {
	&"approaches": [Vector2(3968, 1354), Vector2(4032, 1354), Vector2(4096, 1354), Vector2(3616, 1386), Vector2(3664, 1386), Vector2(3712, 1386), Vector2(3808, 1386), Vector2(3840, 1386), Vector2(3872, 1386), Vector2(3968, 1450), Vector2(4000, 1450), Vector2(4032, 1450), Vector2(3488, 1482), Vector2(3696, 1482), Vector2(3904, 1482), Vector2(4096, 1482)],
	&"band": 1,
	&"floor_steps": [Rect2(3936, 1472, 128, 32)],
	"id": 7,
	"kind": "normal",
	"rect": Rect2(3456, 800, 736, 704),
	&"region": 0,
	&"rocks": [Rect2(3904, 800, 160, 160), Rect2(3520, 800, 64, 96)],
	&"shelves": [Rect2(3584, 1408, 160, 16), Rect2(3936, 1376, 192, 16), Rect2(3776, 1408, 128, 16)]
	}, {
	&"approaches": [Vector2(10144, 2090), Vector2(10192, 2090), Vector2(10240, 2090), Vector2(10208, 2186), Vector2(10256, 2186), Vector2(10304, 2186), Vector2(10112, 2346), Vector2(10192, 2346), Vector2(10272, 2346), Vector2(10112, 2506), Vector2(10208, 2506), Vector2(10304, 2506), Vector2(9792, 2570), Vector2(9792, 2570), Vector2(9792, 2570), Vector2(9920, 2634), Vector2(9968, 2634), Vector2(10016, 2634), Vector2(9408, 2666), Vector2(9568, 2666), Vector2(9728, 2666), Vector2(9856, 2666), Vector2(9856, 2666), Vector2(9856, 2666), Vector2(10080, 2666), Vector2(10480, 2666), Vector2(10880, 2666)],
	&"band": 2,
	&"floor_steps": [Rect2(9888, 2656, 160, 32)],
	"id": 8,
	"kind": "normal",
	"rect": Rect2(9408, 2080, 1504, 608),
	&"region": 2,
	&"rocks": [Rect2(9760, 2592, 64, 96)],
	&"shelves": [Rect2(10112, 2112, 160, 16), Rect2(10176, 2208, 160, 16), Rect2(10080, 2368, 224, 16), Rect2(10080, 2528, 256, 16)]
	}, {
	&"approaches": [Vector2(9216, 618), Vector2(9296, 618), Vector2(9376, 618), Vector2(9472, 618), Vector2(9536, 618), Vector2(9600, 618), Vector2(9760, 650), Vector2(9792, 650), Vector2(9824, 650), Vector2(9216, 714), Vector2(9312, 714), Vector2(9408, 714), Vector2(9152, 746), Vector2(9472, 746), Vector2(9776, 746)],
	&"band": 0,
	&"floor_steps": [Rect2(9184, 736, 256, 32)],
	"id": 9,
	"kind": "normal",
	"rect": Rect2(9120, 256, 768, 512),
	&"region": 2,
	&"rocks": [Rect2(9536, 256, 96, 64), Rect2(9408, 256, 64, 96)],
	&"shelves": [Rect2(9440, 640, 192, 16), Rect2(9184, 640, 224, 16), Rect2(9728, 672, 128, 16)]
	}, {
	&"approaches": [Vector2(10176, 1642), Vector2(10224, 1642), Vector2(10272, 1642), Vector2(10176, 1802), Vector2(10224, 1802), Vector2(10272, 1802), Vector2(10400, 1866), Vector2(10448, 1866), Vector2(10496, 1866), Vector2(9792, 1962), Vector2(10064, 1962), Vector2(10336, 1962), Vector2(10544, 1962)],
	&"band": 1,
	&"floor_steps": [Rect2(10368, 1888, 160, 96)],
	"id": 10,
	"kind": "normal",
	"rect": Rect2(9792, 1536, 768, 448),
	&"region": 2,
	&"rocks": [],
	&"shelves": [Rect2(10144, 1664, 160, 16), Rect2(10144, 1824, 160, 16)]
	}, {
	&"approaches": [Vector2(8480, 618), Vector2(8528, 618), Vector2(8576, 618), Vector2(8736, 618), Vector2(8736, 618), Vector2(8736, 618), Vector2(7936, 714), Vector2(8000, 714), Vector2(8064, 714), Vector2(8480, 714), Vector2(8512, 714), Vector2(8544, 714), Vector2(7680, 746), Vector2(7776, 746), Vector2(7872, 746), Vector2(8128, 746), Vector2(8272, 746), Vector2(8416, 746), Vector2(8608, 746), Vector2(8640, 746), Vector2(8672, 746), Vector2(8800, 746)],
	&"band": 0,
	&"floor_steps": [Rect2(8448, 736, 128, 32), Rect2(7904, 736, 192, 32)],
	"id": 11,
	"kind": "normal",
	"rect": Rect2(7648, 384, 1248, 384),
	&"region": 2,
	&"rocks": [Rect2(8544, 384, 160, 96), Rect2(8704, 640, 64, 128)],
	&"shelves": [Rect2(8448, 640, 160, 16)]
	}, {
	&"approaches": [Vector2(11040, 842), Vector2(11104, 842), Vector2(11168, 842), Vector2(11008, 1002), Vector2(11088, 1002), Vector2(11168, 1002), Vector2(11040, 1162), Vector2(11104, 1162), Vector2(11168, 1162), Vector2(10592, 1258), Vector2(10688, 1258), Vector2(10784, 1258), Vector2(10048, 1322), Vector2(10288, 1322), Vector2(10528, 1322), Vector2(10848, 1322), Vector2(11104, 1322), Vector2(11360, 1322)],
	&"band": 1,
	&"floor_steps": [Rect2(10560, 1280, 256, 64)],
	"id": 12,
	"kind": "normal",
	"rect": Rect2(10016, 832, 1376, 512),
	&"region": 2,
	&"rocks": [Rect2(10432, 832, 96, 160)],
	&"shelves": [Rect2(11008, 864, 192, 16), Rect2(10976, 1024, 224, 16), Rect2(11008, 1184, 192, 16)]
	}, {
	&"approaches": [Vector2(2560, 1834), Vector2(2624, 1834), Vector2(2688, 1834), Vector2(2528, 1994), Vector2(2592, 1994), Vector2(2656, 1994), Vector2(2560, 2154), Vector2(2640, 2154), Vector2(2720, 2154), Vector2(2848, 2250), Vector2(2944, 2250), Vector2(3040, 2250), Vector2(2448, 2314), Vector2(2784, 2314), Vector2(3104, 2314)],
	&"band": 2,
	&"floor_steps": [Rect2(2816, 2272, 256, 64)],
	"id": 13,
	"kind": "normal",
	"rect": Rect2(2336, 1760, 1024, 576),
	&"region": 0,
	&"rocks": [Rect2(2976, 1760, 128, 192)],
	&"shelves": [Rect2(2528, 1856, 192, 16), Rect2(2496, 2016, 192, 16), Rect2(2528, 2176, 224, 16)]
	}, {
	&"approaches": [Vector2(8576, 1450), Vector2(8656, 1450), Vector2(8736, 1450), Vector2(8544, 1610), Vector2(8608, 1610), Vector2(8672, 1610), Vector2(8768, 1642), Vector2(8864, 1642), Vector2(8960, 1642), Vector2(8160, 1738), Vector2(8208, 1738), Vector2(8256, 1738), Vector2(7872, 1770), Vector2(7984, 1770), Vector2(8096, 1770), Vector2(8320, 1770), Vector2(8704, 1770)],
	&"band": 1,
	&"floor_steps": [Rect2(8128, 1760, 160, 32)],
	"id": 14,
	"kind": "normal",
	"rect": Rect2(7872, 1408, 1216, 384),
	&"region": 2,
	&"rocks": [],
	&"shelves": [Rect2(8544, 1472, 224, 16), Rect2(8512, 1632, 192, 16), Rect2(8736, 1664, 256, 16)]
	}, {
	&"approaches": [Vector2(864, 2218), Vector2(896, 2218), Vector2(928, 2218), Vector2(1280, 2250), Vector2(1328, 2250), Vector2(1376, 2250), Vector2(1568, 2250), Vector2(1648, 2250), Vector2(1728, 2250), Vector2(864, 2314), Vector2(928, 2314), Vector2(992, 2314), Vector2(736, 2346), Vector2(768, 2346), Vector2(800, 2346), Vector2(1056, 2346), Vector2(1280, 2346), Vector2(1504, 2346), Vector2(1792, 2346)],
	&"band": 2,
	&"floor_steps": [Rect2(832, 2336, 192, 32), Rect2(1536, 2272, 224, 96)],
	"id": 15,
	"kind": "normal",
	"rect": Rect2(704, 1664, 1152, 704),
	&"region": 0,
	&"rocks": [Rect2(768, 1664, 160, 192), Rect2(1120, 1664, 96, 96)],
	&"shelves": [Rect2(1248, 2272, 160, 16), Rect2(832, 2240, 128, 16)]
	}, {
	&"approaches": [Vector2(4416, 554), Vector2(4496, 554), Vector2(4576, 554), Vector2(4704, 554), Vector2(4800, 554), Vector2(4896, 554), Vector2(4992, 554), Vector2(5024, 554), Vector2(5056, 554), Vector2(4512, 650), Vector2(4608, 650), Vector2(4704, 650), Vector2(4256, 682), Vector2(4352, 682), Vector2(4448, 682), Vector2(4768, 682), Vector2(4928, 682), Vector2(5088, 682)],
	&"band": 0,
	&"floor_steps": [Rect2(4480, 672, 256, 32)],
	"id": 16,
	"kind": "normal",
	"rect": Rect2(4224, 128, 896, 576),
	&"region": 1,
	&"rocks": [Rect2(4608, 128, 160, 64)],
	&"shelves": [Rect2(4384, 576, 224, 16), Rect2(4672, 576, 256, 16), Rect2(4960, 576, 128, 16)]
	}, {
	&"approaches": [Vector2(7232, 1162), Vector2(7312, 1162), Vector2(7392, 1162), Vector2(6688, 1194), Vector2(6720, 1194), Vector2(6752, 1194), Vector2(6944, 1258), Vector2(7008, 1258), Vector2(7072, 1258), Vector2(6496, 1290), Vector2(6624, 1290), Vector2(6816, 1290), Vector2(6848, 1290), Vector2(6880, 1290), Vector2(7136, 1290)],
	&"band": 1,
	&"floor_steps": [Rect2(6912, 1280, 192, 32), Rect2(6656, 1216, 128, 96)],
	"id": 17,
	"kind": "normal",
	"rect": Rect2(6400, 640, 1152, 672),
	&"region": 1,
	&"rocks": [Rect2(6752, 640, 96, 192)],
	&"shelves": [Rect2(7200, 1184, 224, 16)]
	}, {
	&"approaches": [Vector2(7392, 1482), Vector2(7424, 1482), Vector2(7456, 1482), Vector2(7424, 1642), Vector2(7456, 1642), Vector2(7488, 1642), Vector2(7232, 1674), Vector2(7280, 1674), Vector2(7328, 1674), Vector2(7584, 1706), Vector2(7632, 1706), Vector2(7680, 1706), Vector2(7136, 1802), Vector2(7472, 1802)],
	&"band": 1,
	&"floor_steps": [],
	"id": 18,
	"kind": "normal",
	"rect": Rect2(7104, 1472, 640, 352),
	&"region": 1,
	&"rocks": [],
	&"shelves": [Rect2(7360, 1504, 128, 16), Rect2(7392, 1664, 128, 16), Rect2(7200, 1696, 160, 16), Rect2(7552, 1728, 160, 16)]
	}, {
	&"approaches": [Vector2(8192, 874), Vector2(8256, 874), Vector2(8320, 874), Vector2(8192, 970), Vector2(8256, 970), Vector2(8320, 970), Vector2(8192, 1130), Vector2(8256, 1130), Vector2(8320, 1130), Vector2(8000, 1290), Vector2(8864, 1290)],
	&"band": 1,
	&"floor_steps": [],
	"id": 19,
	"kind": "normal",
	"rect": Rect2(7968, 864, 928, 448),
	&"region": 2,
	&"rocks": [],
	&"shelves": [Rect2(8160, 896, 192, 16), Rect2(8160, 992, 192, 16), Rect2(8160, 1152, 192, 16)]
	}],
	"connection_candidates": [{
	"a": 18,
	"b": 14,
	"height": 256,
	&"id": 6,
	"pieces": [Rect2(7712, 1568, 64, 256), Rect2(7776, 1568, 64, 256), Rect2(7840, 1536, 64, 256)],
	"rect": Rect2(7712, 1536, 192, 288),
	"type": "tunnel",
	&"weight": 138.24
	}, {
	"a": 11,
	"b": 9,
	"height": 224,
	&"id": 8,
	"pieces": [Rect2(8864, 544, 64, 224), Rect2(8928, 544, 64, 224), Rect2(8992, 544, 64, 224), Rect2(9056, 544, 64, 224), Rect2(9120, 544, 32, 224)],
	"rect": Rect2(8864, 544, 288, 224),
	"type": "tunnel",
	&"weight": 204.48
	}, {
	"a": 4,
	"b": 0,
	"height": 256,
	&"id": 0,
	"pieces": [Rect2(5024, 2112, 64, 256), Rect2(5088, 2112, 64, 256), Rect2(5152, 2080, 64, 256), Rect2(5216, 2080, 64, 256), Rect2(5280, 2080, 64, 256), Rect2(5344, 2048, 64, 256), Rect2(5408, 2048, 32, 256)],
	"rect": Rect2(5024, 2048, 416, 320),
	"type": "tunnel",
	&"weight": 386.88
	}, {
	"a": 17,
	"b": 19,
	"height": 192,
	&"id": 5,
	"pieces": [Rect2(7520, 1120, 64, 192), Rect2(7584, 1120, 64, 192), Rect2(7648, 1120, 64, 192), Rect2(7712, 1120, 64, 192), Rect2(7776, 1120, 64, 192), Rect2(7840, 1120, 64, 192), Rect2(7904, 1120, 64, 192), Rect2(7968, 1120, 32, 192)],
	"rect": Rect2(7520, 1120, 480, 192),
	"type": "tunnel",
	&"weight": 398.4
	}, {
	"a": 15,
	"b": 13,
	"height": 192,
	&"id": 3,
	"pieces": [Rect2(1824, 2176, 64, 192), Rect2(1888, 2176, 64, 192), Rect2(1952, 2176, 64, 192), Rect2(2016, 2176, 64, 192), Rect2(2080, 2144, 64, 192), Rect2(2144, 2144, 64, 192), Rect2(2208, 2144, 64, 192), Rect2(2272, 2144, 64, 192), Rect2(2336, 2144, 32, 192)],
	"rect": Rect2(1824, 2144, 544, 224),
	"type": "tunnel",
	&"weight": 500.48
	}, {
	"a": 17,
	"b": 18,
	&"id": 3,
	&"platforms": [Rect2(7360, 1312, 160, 16), Rect2(7360, 1408, 160, 16), Rect2(7360, 1504, 128, 16), Rect2(7392, 1664, 128, 16)],
	"rect": Rect2(7360, 1312, 160, 512),
	"type": "shaft",
	&"weight": 547.84
	}, {
	"a": 10,
	"b": 8,
	&"id": 5,
	&"platforms": [Rect2(10080, 1984, 256, 16), Rect2(10112, 2112, 160, 16), Rect2(10176, 2208, 160, 16), Rect2(10080, 2368, 224, 16), Rect2(10080, 2528, 256, 16)],
	"rect": Rect2(10080, 1984, 256, 704),
	"type": "shaft",
	&"weight": 626.56
	}, {
	"a": 7,
	"b": 5,
	"height": 224,
	&"id": 1,
	"pieces": [Rect2(4160, 1280, 64, 224), Rect2(4224, 1280, 64, 224), Rect2(4288, 1280, 64, 224), Rect2(4352, 1280, 64, 224), Rect2(4416, 1248, 64, 224), Rect2(4480, 1248, 64, 224), Rect2(4544, 1248, 64, 224), Rect2(4608, 1248, 64, 224), Rect2(4672, 1248, 32, 224)],
	"rect": Rect2(4160, 1248, 544, 256),
	"type": "tunnel",
	&"weight": 652.8
	}, {
	"a": 6,
	"b": 8,
	"height": 160,
	&"id": 7,
	"pieces": [Rect2(8992, 2368, 64, 160), Rect2(9056, 2400, 64, 160), Rect2(9120, 2432, 64, 160), Rect2(9184, 2464, 64, 160), Rect2(9248, 2464, 64, 160), Rect2(9312, 2496, 64, 160), Rect2(9376, 2528, 64, 160)],
	"rect": Rect2(8992, 2368, 448, 320),
	"type": "tunnel",
	&"weight": 654.08
	}, {
	"a": 9,
	"b": 3,
	"height": 224,
	&"id": 9,
	"pieces": [Rect2(9856, 544, 64, 224), Rect2(9920, 544, 64, 224), Rect2(9984, 544, 64, 224), Rect2(10048, 544, 64, 224), Rect2(10112, 512, 64, 224), Rect2(10176, 512, 64, 224), Rect2(10240, 512, 64, 224)],
	"rect": Rect2(9856, 512, 448, 256),
	"type": "tunnel",
	&"weight": 658.56
	}, {
	"a": 14,
	"b": 6,
	&"id": 4,
	&"platforms": [Rect2(8736, 1792, 256, 16), Rect2(8768, 1920, 192, 16), Rect2(8768, 2048, 192, 16), Rect2(8832, 2208, 160, 16), Rect2(8736, 2368, 256, 16)],
	"rect": Rect2(8736, 1792, 256, 736),
	"type": "shaft",
	&"weight": 721.28
	}, {
	"a": 19,
	"b": 14,
	&"id": 10,
	&"platforms": [Rect2(8480, 1312, 288, 16), Rect2(8544, 1472, 224, 16), Rect2(8512, 1632, 192, 16)],
	"rect": Rect2(8480, 1312, 288, 480),
	"type": "shaft",
	&"weight": 758.4
	}, {
	"a": 11,
	"b": 19,
	&"id": 6,
	&"platforms": [Rect2(8160, 768, 224, 16), Rect2(8160, 896, 192, 16), Rect2(8160, 992, 192, 16), Rect2(8160, 1152, 192, 16)],
	"rect": Rect2(8160, 768, 224, 544),
	"type": "shaft",
	&"weight": 761.6
	}, {
	"a": 3,
	"b": 12,
	&"id": 7,
	&"platforms": [Rect2(10976, 736, 256, 16), Rect2(11008, 864, 192, 16), Rect2(10976, 1024, 224, 16), Rect2(11008, 1184, 192, 16)],
	"rect": Rect2(10976, 736, 256, 608),
	"type": "shaft",
	&"weight": 790.4
	}, {
	"a": 14,
	"b": 10,
	"height": 224,
	&"id": 10,
	"pieces": [Rect2(9056, 1568, 64, 224), Rect2(9120, 1600, 64, 224), Rect2(9184, 1600, 64, 224), Rect2(9248, 1632, 64, 224), Rect2(9312, 1632, 64, 224), Rect2(9376, 1664, 64, 224), Rect2(9440, 1664, 64, 224), Rect2(9504, 1696, 64, 224), Rect2(9568, 1696, 64, 224), Rect2(9632, 1728, 64, 224), Rect2(9696, 1728, 64, 224), Rect2(9760, 1760, 64, 224)],
	"rect": Rect2(9056, 1568, 768, 416),
	"type": "tunnel",
	&"weight": 829.44
	}, {
	"a": 1,
	"b": 13,
	&"id": 1,
	&"platforms": [Rect2(2496, 1216, 256, 16), Rect2(2496, 1376, 256, 16), Rect2(2528, 1536, 160, 16), Rect2(2560, 1696, 192, 16), Rect2(2528, 1856, 192, 16), Rect2(2496, 2016, 192, 16), Rect2(2528, 2176, 224, 16)],
	"rect": Rect2(2496, 1216, 256, 1120),
	"type": "shaft",
	&"weight": 840.0
	}, {
	"a": 18,
	"b": 2,
	&"id": 8,
	&"platforms": [Rect2(7168, 1824, 256, 16), Rect2(7200, 1952, 192, 16), Rect2(7264, 2112, 160, 16), Rect2(7200, 2240, 224, 16), Rect2(7200, 2400, 224, 16), Rect2(7200, 2560, 224, 16)],
	"rect": Rect2(7168, 1824, 256, 896),
	"type": "shaft",
	&"weight": 869.12
	}, {
	"a": 12,
	"b": 10,
	&"id": 9,
	&"platforms": [Rect2(10080, 1344, 256, 16), Rect2(10144, 1504, 192, 16), Rect2(10144, 1664, 160, 16), Rect2(10144, 1824, 160, 16)],
	"rect": Rect2(10080, 1344, 256, 640),
	"type": "shaft",
	&"weight": 966.4
	}, {
	"a": 2,
	"b": 6,
	"height": 192,
	"pieces": [Rect2(7520, 2528, 64, 192), Rect2(7584, 2528, 64, 192), Rect2(7648, 2496, 64, 192), Rect2(7712, 2496, 64, 192), Rect2(7776, 2464, 64, 192), Rect2(7840, 2464, 64, 192), Rect2(7904, 2432, 64, 192), Rect2(7968, 2432, 64, 192), Rect2(8032, 2400, 64, 192), Rect2(8096, 2400, 64, 192), Rect2(8160, 2368, 64, 192), Rect2(8224, 2368, 64, 192), Rect2(8288, 2336, 64, 192), Rect2(8352, 2336, 32, 192)],
	"rect": Rect2(7520, 2336, 864, 384),
	"type": "tunnel",
	&"weight": 967.68
	}, {
	"a": 5,
	"b": 4,
	&"id": 0,
	&"platforms": [Rect2(4736, 1472, 288, 16), Rect2(4800, 1600, 224, 16), Rect2(4736, 1728, 192, 16), Rect2(4736, 1888, 192, 16), Rect2(4736, 2048, 192, 16), Rect2(4736, 2208, 192, 16)],
	"rect": Rect2(4736, 1472, 288, 896),
	"type": "shaft",
	&"weight": 1093.12
	}, {
	"a": 13,
	"b": 4,
	"height": 192,
	&"id": 2,
	"pieces": [Rect2(3328, 2144, 64, 192), Rect2(3392, 2144, 64, 192), Rect2(3456, 2144, 64, 192), Rect2(3520, 2144, 64, 192), Rect2(3584, 2144, 64, 192), Rect2(3648, 2144, 64, 192), Rect2(3712, 2144, 64, 192), Rect2(3776, 2176, 64, 192), Rect2(3840, 2176, 64, 192), Rect2(3904, 2176, 64, 192), Rect2(3968, 2176, 64, 192), Rect2(4032, 2176, 64, 192), Rect2(4096, 2176, 64, 192), Rect2(4160, 2176, 64, 192), Rect2(4224, 2176, 64, 192)],
	"rect": Rect2(3328, 2144, 960, 224),
	"type": "tunnel",
	&"weight": 1161.6
	}, {
	"a": 17,
	"b": 2,
	"rect": Rect2(6496, 1312, 192, 1408),
	"type": "shaft",
	&"weight": 1182.72
	}, {
	"a": 16,
	"b": 5,
	&"id": 2,
	&"platforms": [Rect2(4800, 704, 224, 16), Rect2(4800, 832, 224, 16), Rect2(4832, 992, 192, 16), Rect2(4800, 1152, 224, 16), Rect2(4800, 1312, 192, 16)],
	"rect": Rect2(4800, 704, 224, 768),
	"type": "shaft",
	&"weight": 1198.08
	}, {
	"a": 5,
	"b": 17,
	"height": 224,
	&"id": 4,
	"pieces": [Rect2(5632, 1248, 64, 224), Rect2(5696, 1248, 64, 224), Rect2(5760, 1216, 64, 224), Rect2(5824, 1216, 64, 224), Rect2(5888, 1184, 64, 224), Rect2(5952, 1184, 64, 224), Rect2(6016, 1152, 64, 224), Rect2(6080, 1152, 64, 224), Rect2(6144, 1152, 64, 224), Rect2(6208, 1120, 64, 224), Rect2(6272, 1120, 64, 224), Rect2(6336, 1088, 64, 224), Rect2(6400, 1088, 32, 224)],
	"rect": Rect2(5632, 1088, 800, 384),
	"type": "tunnel",
	&"weight": 1240.0
	}, {
	"a": 9,
	"b": 8,
	"rect": Rect2(9536, 768, 160, 1920),
	"type": "shaft",
	&"weight": 1728.0
	}],
	"erodible_surfaces": [Rect2(5440, 1472, 96, 64), Rect2(8352, 2528, 64, 64), Rect2(3456, 1504, 192, 64), Rect2(3712, 1504, 96, 64), Rect2(9536, 2688, 160, 64), Rect2(10432, 2688, 480, 64), Rect2(9568, 768, 192, 64), Rect2(7648, 768, 192, 64), Rect2(10432, 1344, 64, 64), Rect2(11328, 1344, 64, 64), Rect2(3136, 2336, 96, 64), Rect2(8000, 1792, 64, 64), Rect2(8352, 1792, 32, 64), Rect2(704, 2368, 64, 64), Rect2(1088, 2368, 224, 64), Rect2(1376, 2368, 96, 64), Rect2(4224, 704, 192, 64), Rect2(6528, 1312, 64, 64), Rect2(7168, 1312, 96, 64), Rect2(7648, 1312, 64, 64), Rect2(7712, 1312, 64, 64), Rect2(7776, 1312, 64, 64), Rect2(7840, 1312, 32, 64), Rect2(8992, 768, 32, 64)],
	"fallback": true,
	"landmarks": [{
	"id": 0,
	"name": "翠の水路の守護者",
	"position": Vector2(2592, 1158)
	}, {
	"id": 1,
	"name": "紫晶の回廊の守護者",
	"position": Vector2(7264, 2662)
	}, {
	"id": 2,
	"name": "灰燼の遺構の守護者",
	"position": Vector2(10752, 678)
	}],
	"protected_rects": [Rect2(5344, 1600, 1088, 768), Rect2(2048, 544, 1344, 736), Rect2(6368, 2080, 1248, 704), Rect2(10208, 64, 1504, 736), Rect2(4928, 1952, 608, 512), Rect2(4960, 2080, 192, 416), Rect2(5312, 2016, 192, 416), Rect2(4640, 1376, 480, 1152), Rect2(4064, 1152, 736, 448), Rect2(4096, 1248, 192, 384), Rect2(4576, 1216, 192, 384), Rect2(3232, 2048, 1152, 416), Rect2(3264, 2112, 192, 352), Rect2(4160, 2144, 192, 352), Rect2(1728, 2048, 736, 416), Rect2(1760, 2144, 192, 352), Rect2(2240, 2112, 192, 352), Rect2(2400, 1120, 448, 1376), Rect2(4704, 608, 416, 1024), Rect2(5536, 992, 992, 576), Rect2(5568, 1216, 192, 384), Rect2(6304, 1056, 192, 384), Rect2(7456, 1088, 192, 352), Rect2(7872, 1088, 192, 352), Rect2(7264, 1216, 352, 768), Rect2(7616, 1440, 384, 480), Rect2(7648, 1536, 192, 416), Rect2(7776, 1504, 192, 416), Rect2(8640, 1696, 448, 992), Rect2(8896, 2272, 640, 512), Rect2(8928, 2336, 192, 320), Rect2(9312, 2496, 192, 320), Rect2(9984, 1888, 448, 960), Rect2(8064, 672, 416, 800), Rect2(8800, 512, 192, 384), Rect2(9024, 512, 192, 384), Rect2(9760, 416, 640, 448), Rect2(9792, 512, 192, 384), Rect2(10176, 480, 192, 384), Rect2(10880, 640, 448, 864), Rect2(7072, 1728, 448, 1152), Rect2(9984, 1248, 448, 896), Rect2(8384, 1216, 480, 736), Rect2(8960, 1472, 960, 608), Rect2(8992, 1536, 192, 384), Rect2(9696, 1728, 192, 384), Rect2(5504, 2272, 64, 128), Rect2(6208, 2272, 64, 128), Rect2(5696, 2272, 64, 128), Rect2(5920, 2272, 64, 128), Rect2(2528, 1184, 64, 128), Rect2(7296, 2688, 64, 128), Rect2(7296, 2688, 64, 128), Rect2(7296, 2688, 64, 128), Rect2(10784, 704, 64, 128), Rect2(4800, 2336, 64, 128), Rect2(4800, 2336, 64, 128), Rect2(4800, 2336, 64, 128), Rect2(4800, 2336, 64, 128), Rect2(4320, 2304, 320, 192), Rect2(4896, 1440, 64, 128), Rect2(4896, 1440, 64, 128), Rect2(4896, 1440, 64, 128), Rect2(4864, 1440, 64, 128), Rect2(5120, 1344, 320, 256), Rect2(8832, 2496, 64, 128), Rect2(8896, 2496, 64, 128), Rect2(8832, 2496, 64, 128), Rect2(8416, 2368, 352, 288), Rect2(3648, 1472, 64, 128), Rect2(4000, 1472, 64, 128), Rect2(3808, 1472, 64, 128), Rect2(3872, 1440, 256, 192), Rect2(10176, 2656, 64, 128), Rect2(10240, 2656, 64, 128), Rect2(10176, 2656, 64, 128), Rect2(10176, 2656, 64, 128), Rect2(9824, 2624, 288, 192), Rect2(9696, 2560, 192, 256), Rect2(9504, 736, 64, 128), Rect2(9280, 736, 64, 128), Rect2(9760, 736, 64, 128), Rect2(9120, 704, 384, 192), Rect2(10208, 1952, 64, 128), Rect2(10208, 1952, 64, 128), Rect2(10304, 1856, 288, 256), Rect2(8512, 736, 64, 128), Rect2(8384, 704, 256, 192), Rect2(7840, 704, 320, 192), Rect2(8640, 608, 192, 288), Rect2(11072, 1312, 64, 128), Rect2(11072, 1312, 64, 128), Rect2(11072, 1312, 64, 128), Rect2(10496, 1248, 384, 224), Rect2(2592, 2304, 64, 128), Rect2(2560, 2304, 64, 128), Rect2(2624, 2304, 64, 128), Rect2(2752, 2240, 384, 224), Rect2(8640, 1760, 64, 128), Rect2(8576, 1760, 64, 128), Rect2(8832, 1760, 64, 128), Rect2(8064, 1728, 288, 192), Rect2(1312, 2336, 64, 128), Rect2(864, 2336, 64, 128), Rect2(768, 2304, 320, 192), Rect2(1472, 2240, 352, 256), Rect2(4480, 672, 64, 128), Rect2(4768, 672, 64, 128), Rect2(4992, 672, 64, 128), Rect2(4416, 640, 384, 192), Rect2(7296, 1280, 64, 128), Rect2(6848, 1248, 320, 192), Rect2(6592, 1184, 256, 256), Rect2(7392, 1792, 64, 128), Rect2(7424, 1792, 64, 128), Rect2(7264, 1792, 64, 128), Rect2(7616, 1792, 64, 128), Rect2(8224, 1280, 64, 128), Rect2(8224, 1280, 64, 128), Rect2(8224, 1280, 64, 128)],
	"routes": [{
	"boss_id": 0,
	"outward": [{
	"action": "drop",
	"position": Vector2(5328, 2282),
	"target": Vector2(5328, 2314),
	"to": 110,
	"x": 5328.0
	}, {
	"action": "drop",
	"position": Vector2(5136, 2314),
	"target": Vector2(5136, 2346),
	"to": 115,
	"x": 5136.0
	}, {
	"action": "walk",
	"position": Vector2(4608, 2346),
	"x": 4608.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(4608, 2346),
	"target": Vector2(4544, 2314),
	"to": 109,
	"x": 4608.0
	}, {
	"action": "drop",
	"position": Vector2(4368, 2314),
	"target": Vector2(4368, 2346),
	"to": 114,
	"x": 4368.0
	}, {
	"action": "walk",
	"position": Vector2(3808, 2346),
	"x": 3808.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(3808, 2346),
	"target": Vector2(3744, 2314),
	"to": 108,
	"x": 3808.0
	}, {
	"action": "walk",
	"position": Vector2(3104, 2314),
	"x": 3104.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(3104, 2314),
	"target": Vector2(3040, 2250),
	"to": 104,
	"x": 3104.0
	}, {
	"action": "drop",
	"position": Vector2(2800, 2250),
	"target": Vector2(2800, 2314),
	"to": 107,
	"x": 2800.0
	}, {
	"action": "walk",
	"position": Vector2(2640, 2314),
	"x": 2640.0
	}, {
	"action": "jump",
	"position": Vector2(2640, 2314),
	"target": Vector2(2640, 2154),
	"to": 92,
	"x": 2640.0
	}, {
	"action": "walk",
	"position": Vector2(2608, 2154),
	"x": 2608.0
	}, {
	"action": "jump",
	"position": Vector2(2608, 2154),
	"target": Vector2(2608, 1994),
	"to": 87,
	"x": 2608.0
	}, {
	"action": "walk",
	"position": Vector2(2608, 1994),
	"x": 2608.0
	}, {
	"action": "jump",
	"position": Vector2(2608, 1994),
	"target": Vector2(2608, 1834),
	"to": 76,
	"x": 2608.0
	}, {
	"action": "walk",
	"position": Vector2(2640, 1834),
	"x": 2640.0
	}, {
	"action": "jump",
	"position": Vector2(2640, 1834),
	"target": Vector2(2640, 1674),
	"to": 66,
	"x": 2640.0
	}, {
	"action": "walk",
	"position": Vector2(2624, 1674),
	"x": 2624.0
	}, {
	"action": "jump",
	"position": Vector2(2624, 1674),
	"target": Vector2(2624, 1514),
	"to": 60,
	"x": 2624.0
	}, {
	"action": "walk",
	"position": Vector2(2608, 1514),
	"x": 2608.0
	}, {
	"action": "jump",
	"position": Vector2(2608, 1514),
	"target": Vector2(2608, 1354),
	"to": 43,
	"x": 2608.0
	}, {
	"action": "walk",
	"position": Vector2(2624, 1354),
	"x": 2624.0
	}, {
	"action": "jump",
	"position": Vector2(2624, 1354),
	"target": Vector2(2624, 1194),
	"to": 32,
	"x": 2624.0
	}, {
	"action": "walk",
	"position": Vector2(2592, 1194),
	"x": 2592.0
	}],
	"points": [Vector2(6144, 2282), Vector2(2592, 1194)],
	"returning": [{
	"action": "walk",
	"position": Vector2(2720, 1194),
	"x": 2720.0
	}, {
	"action": "drop_through",
	"position": Vector2(2720, 1194),
	"target": Vector2(2720, 1354),
	"to": 43,
	"x": 2720.0
	}, {
	"action": "walk",
	"position": Vector2(2624, 1354),
	"x": 2624.0
	}, {
	"action": "drop_through",
	"position": Vector2(2624, 1354),
	"target": Vector2(2624, 1514),
	"to": 60,
	"x": 2624.0
	}, {
	"action": "drop",
	"position": Vector2(2512, 1514),
	"target": Vector2(2512, 1994),
	"to": 87,
	"x": 2512.0
	}, {
	"action": "drop",
	"position": Vector2(2480, 1994),
	"target": Vector2(2480, 2314),
	"to": 107,
	"x": 2480.0
	}, {
	"action": "walk",
	"position": Vector2(2784, 2314),
	"x": 2784.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(2784, 2314),
	"target": Vector2(2848, 2250),
	"to": 104,
	"x": 2784.0
	}, {
	"action": "drop",
	"position": Vector2(3088, 2250),
	"target": Vector2(3088, 2314),
	"to": 108,
	"x": 3088.0
	}, {
	"action": "drop",
	"position": Vector2(3792, 2314),
	"target": Vector2(3792, 2346),
	"to": 114,
	"x": 3792.0
	}, {
	"action": "walk",
	"position": Vector2(4352, 2346),
	"x": 4352.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(4352, 2346),
	"target": Vector2(4416, 2314),
	"to": 109,
	"x": 4352.0
	}, {
	"action": "drop",
	"position": Vector2(4592, 2314),
	"target": Vector2(4592, 2346),
	"to": 115,
	"x": 4592.0
	}, {
	"action": "walk",
	"position": Vector2(5120, 2346),
	"x": 5120.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5120, 2346),
	"target": Vector2(5184, 2314),
	"to": 110,
	"x": 5120.0
	}, {
	"action": "walk",
	"position": Vector2(5312, 2314),
	"x": 5312.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5312, 2314),
	"target": Vector2(5376, 2282),
	"to": 105,
	"x": 5312.0
	}, {
	"action": "walk",
	"position": Vector2(6144, 2282),
	"x": 6144.0
	}]
	}, {
	"boss_id": 1,
	"outward": [{
	"action": "drop",
	"position": Vector2(5328, 2282),
	"target": Vector2(5328, 2314),
	"to": 110,
	"x": 5328.0
	}, {
	"action": "drop",
	"position": Vector2(5136, 2314),
	"target": Vector2(5136, 2346),
	"to": 115,
	"x": 5136.0
	}, {
	"action": "walk",
	"position": Vector2(4832, 2346),
	"x": 4832.0
	}, {
	"action": "jump",
	"position": Vector2(4832, 2346),
	"target": Vector2(4832, 2186),
	"to": 95,
	"x": 4832.0
	}, {
	"action": "walk",
	"position": Vector2(4832, 2186),
	"x": 4832.0
	}, {
	"action": "jump",
	"position": Vector2(4832, 2186),
	"target": Vector2(4832, 2026),
	"to": 88,
	"x": 4832.0
	}, {
	"action": "walk",
	"position": Vector2(4832, 2026),
	"x": 4832.0
	}, {
	"action": "jump",
	"position": Vector2(4832, 2026),
	"target": Vector2(4832, 1866),
	"to": 78,
	"x": 4832.0
	}, {
	"action": "walk",
	"position": Vector2(4832, 1866),
	"x": 4832.0
	}, {
	"action": "jump",
	"position": Vector2(4832, 1866),
	"target": Vector2(4832, 1706),
	"to": 68,
	"x": 4832.0
	}, {
	"action": "walk",
	"position": Vector2(4864, 1706),
	"x": 4864.0
	}, {
	"action": "jump",
	"position": Vector2(4864, 1706),
	"target": Vector2(4864, 1578),
	"to": 61,
	"x": 4864.0
	}, {
	"action": "walk",
	"position": Vector2(4912, 1578),
	"x": 4912.0
	}, {
	"action": "jump",
	"position": Vector2(4912, 1578),
	"target": Vector2(4912, 1450),
	"to": 53,
	"x": 4912.0
	}, {
	"action": "walk",
	"position": Vector2(5152, 1450),
	"x": 5152.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(5152, 1450),
	"target": Vector2(5216, 1354),
	"to": 45,
	"x": 5152.0
	}, {
	"action": "drop",
	"position": Vector2(5392, 1354),
	"target": Vector2(5392, 1450),
	"to": 54,
	"x": 5392.0
	}, {
	"action": "walk",
	"position": Vector2(5728, 1450),
	"x": 5728.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5728, 1450),
	"target": Vector2(5792, 1418),
	"to": 51,
	"x": 5728.0
	}, {
	"action": "walk",
	"position": Vector2(5856, 1418),
	"x": 5856.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5856, 1418),
	"target": Vector2(5920, 1386),
	"to": 49,
	"x": 5856.0
	}, {
	"action": "walk",
	"position": Vector2(5984, 1386),
	"x": 5984.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5984, 1386),
	"target": Vector2(6048, 1354),
	"to": 46,
	"x": 5984.0
	}, {
	"action": "walk",
	"position": Vector2(6176, 1354),
	"x": 6176.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(6176, 1354),
	"target": Vector2(6240, 1322),
	"to": 40,
	"x": 6176.0
	}, {
	"action": "walk",
	"position": Vector2(6304, 1322),
	"x": 6304.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(6304, 1322),
	"target": Vector2(6368, 1290),
	"to": 37,
	"x": 6304.0
	}, {
	"action": "walk",
	"position": Vector2(6624, 1290),
	"x": 6624.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(6624, 1290),
	"target": Vector2(6688, 1194),
	"to": 33,
	"x": 6624.0
	}, {
	"action": "drop",
	"position": Vector2(6800, 1194),
	"target": Vector2(6800, 1290),
	"to": 38,
	"x": 6800.0
	}, {
	"action": "walk",
	"position": Vector2(6880, 1290),
	"x": 6880.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(6880, 1290),
	"target": Vector2(6944, 1258),
	"to": 34,
	"x": 6880.0
	}, {
	"action": "drop",
	"position": Vector2(7120, 1258),
	"target": Vector2(7120, 1290),
	"to": 39,
	"x": 7120.0
	}, {
	"action": "walk",
	"position": Vector2(7440, 1290),
	"x": 7440.0
	}, {
	"action": "drop_through",
	"position": Vector2(7440, 1290),
	"target": Vector2(7440, 1386),
	"to": 50,
	"x": 7440.0
	}, {
	"action": "walk",
	"position": Vector2(7440, 1386),
	"x": 7440.0
	}, {
	"action": "drop_through",
	"position": Vector2(7440, 1386),
	"target": Vector2(7440, 1482),
	"to": 58,
	"x": 7440.0
	}, {
	"action": "walk",
	"position": Vector2(7424, 1482),
	"x": 7424.0
	}, {
	"action": "drop_through",
	"position": Vector2(7424, 1482),
	"target": Vector2(7424, 1642),
	"to": 63,
	"x": 7424.0
	}, {
	"action": "walk",
	"position": Vector2(7456, 1642),
	"x": 7456.0
	}, {
	"action": "drop_through",
	"position": Vector2(7456, 1642),
	"target": Vector2(7456, 1802),
	"to": 73,
	"x": 7456.0
	}, {
	"action": "walk",
	"position": Vector2(7296, 1802),
	"x": 7296.0
	}, {
	"action": "drop_through",
	"position": Vector2(7296, 1802),
	"target": Vector2(7296, 1930),
	"to": 83,
	"x": 7296.0
	}, {
	"action": "drop",
	"position": Vector2(7184, 1930),
	"target": Vector2(7184, 2698),
	"to": 133,
	"x": 7184.0
	}, {
	"action": "walk",
	"position": Vector2(7264, 2698),
	"x": 7264.0
	}],
	"points": [Vector2(6144, 2282), Vector2(7264, 2698)],
	"returning": [{
	"action": "walk",
	"position": Vector2(7312, 2698),
	"x": 7312.0
	}, {
	"action": "jump",
	"position": Vector2(7312, 2698),
	"target": Vector2(7312, 2538),
	"to": 123,
	"x": 7312.0
	}, {
	"action": "walk",
	"position": Vector2(7312, 2538),
	"x": 7312.0
	}, {
	"action": "jump",
	"position": Vector2(7312, 2538),
	"target": Vector2(7312, 2378),
	"to": 118,
	"x": 7312.0
	}, {
	"action": "walk",
	"position": Vector2(7312, 2378),
	"x": 7312.0
	}, {
	"action": "jump",
	"position": Vector2(7312, 2378),
	"target": Vector2(7312, 2218),
	"to": 101,
	"x": 7312.0
	}, {
	"action": "walk",
	"position": Vector2(7344, 2218),
	"x": 7344.0
	}, {
	"action": "jump",
	"position": Vector2(7344, 2218),
	"target": Vector2(7344, 2090),
	"to": 90,
	"x": 7344.0
	}, {
	"action": "walk",
	"position": Vector2(7328, 2090),
	"x": 7328.0
	}, {
	"action": "jump",
	"position": Vector2(7328, 2090),
	"target": Vector2(7328, 1930),
	"to": 83,
	"x": 7328.0
	}, {
	"action": "walk",
	"position": Vector2(7296, 1930),
	"x": 7296.0
	}, {
	"action": "jump",
	"position": Vector2(7296, 1930),
	"target": Vector2(7296, 1802),
	"to": 73,
	"x": 7296.0
	}, {
	"action": "walk",
	"position": Vector2(7456, 1802),
	"x": 7456.0
	}, {
	"action": "jump",
	"position": Vector2(7456, 1802),
	"target": Vector2(7456, 1642),
	"to": 63,
	"x": 7456.0
	}, {
	"action": "walk",
	"position": Vector2(7440, 1642),
	"x": 7440.0
	}, {
	"action": "jump",
	"position": Vector2(7440, 1642),
	"target": Vector2(7440, 1482),
	"to": 58,
	"x": 7440.0
	}, {
	"action": "walk",
	"position": Vector2(7424, 1482),
	"x": 7424.0
	}, {
	"action": "jump",
	"position": Vector2(7424, 1482),
	"target": Vector2(7424, 1386),
	"to": 50,
	"x": 7424.0
	}, {
	"action": "walk",
	"position": Vector2(7440, 1386),
	"x": 7440.0
	}, {
	"action": "jump",
	"position": Vector2(7440, 1386),
	"target": Vector2(7440, 1290),
	"to": 39,
	"x": 7440.0
	}, {
	"action": "walk",
	"position": Vector2(7136, 1290),
	"x": 7136.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(7136, 1290),
	"target": Vector2(7072, 1258),
	"to": 34,
	"x": 7136.0
	}, {
	"action": "drop",
	"position": Vector2(6896, 1258),
	"target": Vector2(6896, 1290),
	"to": 38,
	"x": 6896.0
	}, {
	"action": "walk",
	"position": Vector2(6816, 1290),
	"x": 6816.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(6816, 1290),
	"target": Vector2(6752, 1194),
	"to": 33,
	"x": 6816.0
	}, {
	"action": "drop",
	"position": Vector2(6640, 1194),
	"target": Vector2(6640, 1290),
	"to": 37,
	"x": 6640.0
	}, {
	"action": "drop",
	"position": Vector2(6320, 1290),
	"target": Vector2(6320, 1322),
	"to": 40,
	"x": 6320.0
	}, {
	"action": "drop",
	"position": Vector2(6192, 1322),
	"target": Vector2(6192, 1354),
	"to": 46,
	"x": 6192.0
	}, {
	"action": "drop",
	"position": Vector2(6000, 1354),
	"target": Vector2(6000, 1386),
	"to": 49,
	"x": 6000.0
	}, {
	"action": "drop",
	"position": Vector2(5872, 1386),
	"target": Vector2(5872, 1418),
	"to": 51,
	"x": 5872.0
	}, {
	"action": "drop",
	"position": Vector2(5744, 1418),
	"target": Vector2(5744, 1450),
	"to": 54,
	"x": 5744.0
	}, {
	"action": "walk",
	"position": Vector2(5408, 1450),
	"x": 5408.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(5408, 1450),
	"target": Vector2(5344, 1354),
	"to": 45,
	"x": 5408.0
	}, {
	"action": "drop",
	"position": Vector2(5168, 1354),
	"target": Vector2(5168, 1450),
	"to": 53,
	"x": 5168.0
	}, {
	"action": "walk",
	"position": Vector2(4880, 1450),
	"x": 4880.0
	}, {
	"action": "drop_through",
	"position": Vector2(4880, 1450),
	"target": Vector2(4880, 1578),
	"to": 61,
	"x": 4880.0
	}, {
	"action": "walk",
	"position": Vector2(4992, 1578),
	"x": 4992.0
	}, {
	"action": "drop_through",
	"position": Vector2(4992, 1578),
	"target": Vector2(4992, 2346),
	"to": 115,
	"x": 4992.0
	}, {
	"action": "walk",
	"position": Vector2(5120, 2346),
	"x": 5120.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5120, 2346),
	"target": Vector2(5184, 2314),
	"to": 110,
	"x": 5120.0
	}, {
	"action": "walk",
	"position": Vector2(5312, 2314),
	"x": 5312.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5312, 2314),
	"target": Vector2(5376, 2282),
	"to": 105,
	"x": 5312.0
	}, {
	"action": "walk",
	"position": Vector2(6144, 2282),
	"x": 6144.0
	}]
	}, {
	"boss_id": 2,
	"outward": [{
	"action": "drop",
	"position": Vector2(5328, 2282),
	"target": Vector2(5328, 2314),
	"to": 110,
	"x": 5328.0
	}, {
	"action": "drop",
	"position": Vector2(5136, 2314),
	"target": Vector2(5136, 2346),
	"to": 115,
	"x": 5136.0
	}, {
	"action": "walk",
	"position": Vector2(4832, 2346),
	"x": 4832.0
	}, {
	"action": "jump",
	"position": Vector2(4832, 2346),
	"target": Vector2(4832, 2186),
	"to": 95,
	"x": 4832.0
	}, {
	"action": "walk",
	"position": Vector2(4832, 2186),
	"x": 4832.0
	}, {
	"action": "jump",
	"position": Vector2(4832, 2186),
	"target": Vector2(4832, 2026),
	"to": 88,
	"x": 4832.0
	}, {
	"action": "walk",
	"position": Vector2(4832, 2026),
	"x": 4832.0
	}, {
	"action": "jump",
	"position": Vector2(4832, 2026),
	"target": Vector2(4832, 1866),
	"to": 78,
	"x": 4832.0
	}, {
	"action": "walk",
	"position": Vector2(4832, 1866),
	"x": 4832.0
	}, {
	"action": "jump",
	"position": Vector2(4832, 1866),
	"target": Vector2(4832, 1706),
	"to": 68,
	"x": 4832.0
	}, {
	"action": "walk",
	"position": Vector2(4864, 1706),
	"x": 4864.0
	}, {
	"action": "jump",
	"position": Vector2(4864, 1706),
	"target": Vector2(4864, 1578),
	"to": 61,
	"x": 4864.0
	}, {
	"action": "walk",
	"position": Vector2(4912, 1578),
	"x": 4912.0
	}, {
	"action": "jump",
	"position": Vector2(4912, 1578),
	"target": Vector2(4912, 1450),
	"to": 53,
	"x": 4912.0
	}, {
	"action": "walk",
	"position": Vector2(5152, 1450),
	"x": 5152.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(5152, 1450),
	"target": Vector2(5216, 1354),
	"to": 45,
	"x": 5152.0
	}, {
	"action": "drop",
	"position": Vector2(5392, 1354),
	"target": Vector2(5392, 1450),
	"to": 54,
	"x": 5392.0
	}, {
	"action": "walk",
	"position": Vector2(5728, 1450),
	"x": 5728.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5728, 1450),
	"target": Vector2(5792, 1418),
	"to": 51,
	"x": 5728.0
	}, {
	"action": "walk",
	"position": Vector2(5856, 1418),
	"x": 5856.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5856, 1418),
	"target": Vector2(5920, 1386),
	"to": 49,
	"x": 5856.0
	}, {
	"action": "walk",
	"position": Vector2(5984, 1386),
	"x": 5984.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5984, 1386),
	"target": Vector2(6048, 1354),
	"to": 46,
	"x": 5984.0
	}, {
	"action": "walk",
	"position": Vector2(6176, 1354),
	"x": 6176.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(6176, 1354),
	"target": Vector2(6240, 1322),
	"to": 40,
	"x": 6176.0
	}, {
	"action": "walk",
	"position": Vector2(6304, 1322),
	"x": 6304.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(6304, 1322),
	"target": Vector2(6368, 1290),
	"to": 37,
	"x": 6304.0
	}, {
	"action": "walk",
	"position": Vector2(6624, 1290),
	"x": 6624.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(6624, 1290),
	"target": Vector2(6688, 1194),
	"to": 33,
	"x": 6624.0
	}, {
	"action": "drop",
	"position": Vector2(6800, 1194),
	"target": Vector2(6800, 1290),
	"to": 38,
	"x": 6800.0
	}, {
	"action": "walk",
	"position": Vector2(6880, 1290),
	"x": 6880.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(6880, 1290),
	"target": Vector2(6944, 1258),
	"to": 34,
	"x": 6880.0
	}, {
	"action": "drop",
	"position": Vector2(7120, 1258),
	"target": Vector2(7120, 1290),
	"to": 39,
	"x": 7120.0
	}, {
	"action": "walk",
	"position": Vector2(8256, 1290),
	"x": 8256.0
	}, {
	"action": "jump",
	"position": Vector2(8256, 1290),
	"target": Vector2(8256, 1130),
	"to": 29,
	"x": 8256.0
	}, {
	"action": "walk",
	"position": Vector2(8256, 1130),
	"x": 8256.0
	}, {
	"action": "jump",
	"position": Vector2(8256, 1130),
	"target": Vector2(8256, 970),
	"to": 25,
	"x": 8256.0
	}, {
	"action": "walk",
	"position": Vector2(8256, 970),
	"x": 8256.0
	}, {
	"action": "jump",
	"position": Vector2(8256, 970),
	"target": Vector2(8256, 874),
	"to": 23,
	"x": 8256.0
	}, {
	"action": "walk",
	"position": Vector2(8256, 874),
	"x": 8256.0
	}, {
	"action": "jump",
	"position": Vector2(8256, 874),
	"target": Vector2(8256, 746),
	"to": 17,
	"x": 8256.0
	}, {
	"action": "walk",
	"position": Vector2(8416, 746),
	"x": 8416.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(8416, 746),
	"target": Vector2(8480, 618),
	"to": 4,
	"x": 8416.0
	}, {
	"action": "drop",
	"position": Vector2(8624, 618),
	"target": Vector2(8624, 746),
	"to": 18,
	"x": 8624.0
	}, {
	"action": "walk",
	"position": Vector2(8672, 746),
	"x": 8672.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(8672, 746),
	"target": Vector2(8736, 618),
	"to": 5,
	"x": 8672.0
	}, {
	"action": "drop",
	"position": Vector2(8784, 618),
	"target": Vector2(8784, 746),
	"to": 19,
	"x": 8784.0
	}, {
	"action": "walk",
	"position": Vector2(9152, 746),
	"x": 9152.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(9152, 746),
	"target": Vector2(9216, 714),
	"to": 14,
	"x": 9152.0
	}, {
	"action": "drop",
	"position": Vector2(9456, 714),
	"target": Vector2(9456, 746),
	"to": 20,
	"x": 9456.0
	}, {
	"action": "walk",
	"position": Vector2(10080, 746),
	"x": 10080.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(10080, 746),
	"target": Vector2(10144, 714),
	"to": 15,
	"x": 10080.0
	}, {
	"action": "walk",
	"position": Vector2(10752, 714),
	"x": 10752.0
	}],
	"points": [Vector2(6144, 2282), Vector2(10752, 714)],
	"returning": [{
	"action": "drop",
	"position": Vector2(10096, 714),
	"target": Vector2(10096, 746),
	"to": 20,
	"x": 10096.0
	}, {
	"action": "walk",
	"position": Vector2(9472, 746),
	"x": 9472.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(9472, 746),
	"target": Vector2(9376, 618),
	"to": 6,
	"x": 9472.0
	}, {
	"action": "drop",
	"position": Vector2(9168, 618),
	"target": Vector2(9168, 746),
	"to": 19,
	"x": 9168.0
	}, {
	"action": "walk",
	"position": Vector2(8800, 746),
	"x": 8800.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(8800, 746),
	"target": Vector2(8736, 618),
	"to": 5,
	"x": 8800.0
	}, {
	"action": "drop",
	"position": Vector2(8688, 618),
	"target": Vector2(8688, 746),
	"to": 18,
	"x": 8688.0
	}, {
	"action": "walk",
	"position": Vector2(8608, 746),
	"x": 8608.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(8608, 746),
	"target": Vector2(8544, 714),
	"to": 13,
	"x": 8608.0
	}, {
	"action": "drop",
	"position": Vector2(8432, 714),
	"target": Vector2(8432, 746),
	"to": 17,
	"x": 8432.0
	}, {
	"action": "walk",
	"position": Vector2(8272, 746),
	"x": 8272.0
	}, {
	"action": "drop_through",
	"position": Vector2(8272, 746),
	"target": Vector2(8272, 874),
	"to": 23,
	"x": 8272.0
	}, {
	"action": "drop",
	"position": Vector2(8368, 874),
	"target": Vector2(8368, 1290),
	"to": 39,
	"x": 8368.0
	}, {
	"action": "walk",
	"position": Vector2(7136, 1290),
	"x": 7136.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(7136, 1290),
	"target": Vector2(7072, 1258),
	"to": 34,
	"x": 7136.0
	}, {
	"action": "drop",
	"position": Vector2(6896, 1258),
	"target": Vector2(6896, 1290),
	"to": 38,
	"x": 6896.0
	}, {
	"action": "walk",
	"position": Vector2(6816, 1290),
	"x": 6816.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(6816, 1290),
	"target": Vector2(6752, 1194),
	"to": 33,
	"x": 6816.0
	}, {
	"action": "drop",
	"position": Vector2(6640, 1194),
	"target": Vector2(6640, 1290),
	"to": 37,
	"x": 6640.0
	}, {
	"action": "drop",
	"position": Vector2(6320, 1290),
	"target": Vector2(6320, 1322),
	"to": 40,
	"x": 6320.0
	}, {
	"action": "drop",
	"position": Vector2(6192, 1322),
	"target": Vector2(6192, 1354),
	"to": 46,
	"x": 6192.0
	}, {
	"action": "drop",
	"position": Vector2(6000, 1354),
	"target": Vector2(6000, 1386),
	"to": 49,
	"x": 6000.0
	}, {
	"action": "drop",
	"position": Vector2(5872, 1386),
	"target": Vector2(5872, 1418),
	"to": 51,
	"x": 5872.0
	}, {
	"action": "drop",
	"position": Vector2(5744, 1418),
	"target": Vector2(5744, 1450),
	"to": 54,
	"x": 5744.0
	}, {
	"action": "walk",
	"position": Vector2(5408, 1450),
	"x": 5408.0
	}, {
	"action": "jump",
	"hold_frames": 40,
	"position": Vector2(5408, 1450),
	"target": Vector2(5344, 1354),
	"to": 45,
	"x": 5408.0
	}, {
	"action": "drop",
	"position": Vector2(5168, 1354),
	"target": Vector2(5168, 1450),
	"to": 53,
	"x": 5168.0
	}, {
	"action": "walk",
	"position": Vector2(4880, 1450),
	"x": 4880.0
	}, {
	"action": "drop_through",
	"position": Vector2(4880, 1450),
	"target": Vector2(4880, 1578),
	"to": 61,
	"x": 4880.0
	}, {
	"action": "walk",
	"position": Vector2(4992, 1578),
	"x": 4992.0
	}, {
	"action": "drop_through",
	"position": Vector2(4992, 1578),
	"target": Vector2(4992, 2346),
	"to": 115,
	"x": 4992.0
	}, {
	"action": "walk",
	"position": Vector2(5120, 2346),
	"x": 5120.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5120, 2346),
	"target": Vector2(5184, 2314),
	"to": 110,
	"x": 5120.0
	}, {
	"action": "walk",
	"position": Vector2(5312, 2314),
	"x": 5312.0
	}, {
	"action": "jump",
	"hold_frames": 4,
	"position": Vector2(5312, 2314),
	"target": Vector2(5376, 2282),
	"to": 105,
	"x": 5312.0
	}, {
	"action": "walk",
	"position": Vector2(6144, 2282),
	"x": 6144.0
	}]
	}],
	"seed": 4242,
	"shafts": [{
	"a": 5,
	"b": 4,
	&"id": 0,
	&"platforms": [Rect2(4736, 1472, 288, 16), Rect2(4800, 1600, 224, 16), Rect2(4736, 1728, 192, 16), Rect2(4736, 1888, 192, 16), Rect2(4736, 2048, 192, 16), Rect2(4736, 2208, 192, 16)],
	"rect": Rect2(4736, 1472, 288, 896),
	"type": "shaft",
	&"weight": 1093.12
	}, {
	"a": 1,
	"b": 13,
	&"id": 1,
	&"platforms": [Rect2(2496, 1216, 256, 16), Rect2(2496, 1376, 256, 16), Rect2(2528, 1536, 160, 16), Rect2(2560, 1696, 192, 16), Rect2(2528, 1856, 192, 16), Rect2(2496, 2016, 192, 16), Rect2(2528, 2176, 224, 16)],
	"rect": Rect2(2496, 1216, 256, 1120),
	"type": "shaft",
	&"weight": 840.0
	}, {
	"a": 16,
	"b": 5,
	&"id": 2,
	&"platforms": [Rect2(4800, 704, 224, 16), Rect2(4800, 832, 224, 16), Rect2(4832, 992, 192, 16), Rect2(4800, 1152, 224, 16), Rect2(4800, 1312, 192, 16)],
	"rect": Rect2(4800, 704, 224, 768),
	"type": "shaft",
	&"weight": 1198.08
	}, {
	"a": 17,
	"b": 18,
	&"id": 3,
	&"platforms": [Rect2(7360, 1312, 160, 16), Rect2(7360, 1408, 160, 16), Rect2(7360, 1504, 128, 16), Rect2(7392, 1664, 128, 16)],
	"rect": Rect2(7360, 1312, 160, 512),
	"type": "shaft",
	&"weight": 547.84
	}, {
	"a": 14,
	"b": 6,
	&"id": 4,
	&"platforms": [Rect2(8736, 1792, 256, 16), Rect2(8768, 1920, 192, 16), Rect2(8768, 2048, 192, 16), Rect2(8832, 2208, 160, 16), Rect2(8736, 2368, 256, 16)],
	"rect": Rect2(8736, 1792, 256, 736),
	"type": "shaft",
	&"weight": 721.28
	}, {
	"a": 10,
	"b": 8,
	&"id": 5,
	&"platforms": [Rect2(10080, 1984, 256, 16), Rect2(10112, 2112, 160, 16), Rect2(10176, 2208, 160, 16), Rect2(10080, 2368, 224, 16), Rect2(10080, 2528, 256, 16)],
	"rect": Rect2(10080, 1984, 256, 704),
	"type": "shaft",
	&"weight": 626.56
	}, {
	"a": 11,
	"b": 19,
	&"id": 6,
	&"platforms": [Rect2(8160, 768, 224, 16), Rect2(8160, 896, 192, 16), Rect2(8160, 992, 192, 16), Rect2(8160, 1152, 192, 16)],
	"rect": Rect2(8160, 768, 224, 544),
	"type": "shaft",
	&"weight": 761.6
	}, {
	"a": 3,
	"b": 12,
	&"id": 7,
	&"platforms": [Rect2(10976, 736, 256, 16), Rect2(11008, 864, 192, 16), Rect2(10976, 1024, 224, 16), Rect2(11008, 1184, 192, 16)],
	"rect": Rect2(10976, 736, 256, 608),
	"type": "shaft",
	&"weight": 790.4
	}, {
	"a": 18,
	"b": 2,
	&"id": 8,
	&"platforms": [Rect2(7168, 1824, 256, 16), Rect2(7200, 1952, 192, 16), Rect2(7264, 2112, 160, 16), Rect2(7200, 2240, 224, 16), Rect2(7200, 2400, 224, 16), Rect2(7200, 2560, 224, 16)],
	"rect": Rect2(7168, 1824, 256, 896),
	"type": "shaft",
	&"weight": 869.12
	}, {
	"a": 12,
	"b": 10,
	&"id": 9,
	&"platforms": [Rect2(10080, 1344, 256, 16), Rect2(10144, 1504, 192, 16), Rect2(10144, 1664, 160, 16), Rect2(10144, 1824, 160, 16)],
	"rect": Rect2(10080, 1344, 256, 640),
	"type": "shaft",
	&"weight": 966.4
	}, {
	"a": 19,
	"b": 14,
	&"id": 10,
	&"platforms": [Rect2(8480, 1312, 288, 16), Rect2(8544, 1472, 224, 16), Rect2(8512, 1632, 192, 16)],
	"rect": Rect2(8480, 1312, 288, 480),
	"type": "shaft",
	&"weight": 758.4
	}],
	"solids": [Rect2(0, 0, 12288, 128), Rect2(0, 128, 4224, 480), Rect2(5120, 128, 5152, 128), Rect2(11648, 128, 640, 608), Rect2(5120, 256, 4000, 128), Rect2(9888, 256, 384, 256), Rect2(5120, 384, 2528, 256), Rect2(8896, 384, 224, 160), Rect2(9888, 512, 224, 32), Rect2(0, 608, 2112, 608), Rect2(3328, 608, 896, 96), Rect2(5120, 640, 1280, 64), Rect2(7552, 640, 96, 128), Rect2(3328, 704, 1472, 64), Rect2(5024, 704, 1376, 64), Rect2(10112, 736, 864, 32), Rect2(11232, 736, 1056, 96), Rect2(3328, 768, 1344, 32), Rect2(5664, 768, 736, 320), Rect2(7552, 768, 608, 96), Rect2(8384, 768, 2592, 64), Rect2(3328, 800, 128, 416), Rect2(4192, 800, 480, 448), Rect2(8384, 832, 1632, 32), Rect2(11392, 832, 896, 512), Rect2(7552, 864, 416, 256), Rect2(8896, 864, 1120, 448), Rect2(5664, 1088, 672, 32), Rect2(5664, 1120, 544, 32), Rect2(5664, 1152, 352, 32), Rect2(5664, 1184, 224, 32), Rect2(0, 1216, 2496, 448), Rect2(2752, 1216, 704, 288), Rect2(5664, 1216, 96, 32), Rect2(4192, 1248, 224, 32), Rect2(6336, 1312, 1024, 32), Rect2(7520, 1312, 960, 96), Rect2(8768, 1312, 1248, 32), Rect2(6208, 1344, 1152, 32), Rect2(8768, 1344, 1312, 64), Rect2(10336, 1344, 1952, 192), Rect2(6016, 1376, 1344, 32), Rect2(5888, 1408, 1472, 32), Rect2(7520, 1408, 352, 64), Rect2(9088, 1408, 992, 128), Rect2(5760, 1440, 1600, 32), Rect2(4416, 1472, 320, 32), Rect2(5024, 1472, 2080, 192), Rect2(7744, 1472, 128, 64), Rect2(2752, 1504, 1984, 160), Rect2(7744, 1536, 96, 32), Rect2(9088, 1536, 704, 32), Rect2(10560, 1536, 1728, 448), Rect2(9120, 1568, 672, 32), Rect2(9248, 1600, 544, 32), Rect2(9376, 1632, 416, 32), Rect2(0, 1664, 704, 704), Rect2(1856, 1664, 640, 96), Rect2(2752, 1664, 1504, 96), Rect2(5056, 1664, 352, 384), Rect2(6368, 1664, 736, 160), Rect2(9504, 1664, 288, 32), Rect2(9632, 1696, 160, 32), Rect2(9760, 1728, 32, 32), Rect2(1856, 1760, 480, 384), Rect2(3360, 1760, 896, 384), Rect2(7840, 1792, 896, 32), Rect2(8992, 1792, 128, 32), Rect2(6368, 1824, 800, 320), Rect2(7424, 1824, 1312, 192), Rect2(8992, 1824, 256, 32), Rect2(8992, 1856, 384, 32), Rect2(8992, 1888, 512, 32), Rect2(8992, 1920, 640, 32), Rect2(8992, 1952, 768, 32), Rect2(8992, 1984, 1088, 32), Rect2(10336, 1984, 1952, 96), Rect2(7424, 2016, 928, 128), Rect2(9024, 2016, 1056, 64), Rect2(5056, 2048, 288, 32), Rect2(5056, 2080, 96, 32), Rect2(9024, 2080, 384, 288), Rect2(10912, 2080, 1376, 608), Rect2(1856, 2144, 224, 32), Rect2(3776, 2144, 480, 32), Rect2(6368, 2144, 64, 160), Rect2(7552, 2144, 800, 384), Rect2(5344, 2304, 1088, 32), Rect2(2080, 2336, 1696, 32), Rect2(5152, 2336, 1280, 32), Rect2(0, 2368, 6432, 352), Rect2(9056, 2368, 352, 32), Rect2(9120, 2400, 288, 32), Rect2(9184, 2432, 224, 32), Rect2(9312, 2464, 96, 32), Rect2(9376, 2496, 32, 32), Rect2(7552, 2528, 1504, 32), Rect2(7552, 2560, 1568, 32), Rect2(7552, 2592, 1632, 32), Rect2(7552, 2624, 1760, 32), Rect2(7552, 2656, 1824, 32), Rect2(7552, 2688, 4736, 32), Rect2(0, 2720, 12288, 352), Rect2(4736, 1472, 288, 16), Rect2(4800, 1600, 224, 16), Rect2(4736, 1728, 192, 16), Rect2(4736, 1888, 192, 16), Rect2(4736, 2048, 192, 16), Rect2(4736, 2208, 192, 16), Rect2(2496, 1216, 256, 16), Rect2(2496, 1376, 256, 16), Rect2(2528, 1536, 160, 16), Rect2(2560, 1696, 192, 16), Rect2(2528, 1856, 192, 16), Rect2(2496, 2016, 192, 16), Rect2(2528, 2176, 224, 16), Rect2(4800, 704, 224, 16), Rect2(4800, 832, 224, 16), Rect2(4832, 992, 192, 16), Rect2(4800, 1152, 224, 16), Rect2(4800, 1312, 192, 16), Rect2(7360, 1312, 160, 16), Rect2(7360, 1408, 160, 16), Rect2(7360, 1504, 128, 16), Rect2(7392, 1664, 128, 16), Rect2(8736, 1792, 256, 16), Rect2(8768, 1920, 192, 16), Rect2(8768, 2048, 192, 16), Rect2(8832, 2208, 160, 16), Rect2(8736, 2368, 256, 16), Rect2(10080, 1984, 256, 16), Rect2(10112, 2112, 160, 16), Rect2(10176, 2208, 160, 16), Rect2(10080, 2368, 224, 16), Rect2(10080, 2528, 256, 16), Rect2(8160, 768, 224, 16), Rect2(8160, 896, 192, 16), Rect2(8160, 992, 192, 16), Rect2(8160, 1152, 192, 16), Rect2(10976, 736, 256, 16), Rect2(11008, 864, 192, 16), Rect2(10976, 1024, 224, 16), Rect2(11008, 1184, 192, 16), Rect2(7168, 1824, 256, 16), Rect2(7200, 1952, 192, 16), Rect2(7264, 2112, 160, 16), Rect2(7200, 2240, 224, 16), Rect2(7200, 2400, 224, 16), Rect2(7200, 2560, 224, 16), Rect2(10080, 1344, 256, 16), Rect2(10144, 1504, 192, 16), Rect2(10144, 1664, 160, 16), Rect2(10144, 1824, 160, 16), Rect2(8480, 1312, 288, 16), Rect2(8544, 1472, 224, 16), Rect2(8512, 1632, 192, 16), Rect2(5440, 2208, 192, 16), Rect2(6144, 2208, 160, 16), Rect2(5664, 2176, 128, 16), Rect2(5824, 2176, 224, 16), Rect2(2464, 1056, 160, 16), Rect2(10720, 576, 160, 16), Rect2(4384, 2336, 192, 32), Rect2(4448, 1664, 96, 160), Rect2(4288, 1664, 96, 64), Rect2(5184, 1376, 192, 96), Rect2(5344, 768, 96, 192), Rect2(8480, 2400, 224, 128), Rect2(8544, 2016, 64, 160), Rect2(8384, 2016, 96, 128), Rect2(3584, 1408, 160, 16), Rect2(3936, 1376, 192, 16), Rect2(3776, 1408, 128, 16), Rect2(3936, 1472, 128, 32), Rect2(3904, 800, 160, 160), Rect2(3520, 800, 64, 96), Rect2(9888, 2656, 160, 32), Rect2(9760, 2592, 64, 96), Rect2(9440, 640, 192, 16), Rect2(9184, 640, 224, 16), Rect2(9728, 672, 128, 16), Rect2(9184, 736, 256, 32), Rect2(9536, 256, 96, 64), Rect2(9408, 256, 64, 96), Rect2(10368, 1888, 160, 96), Rect2(8448, 640, 160, 16), Rect2(8448, 736, 128, 32), Rect2(7904, 736, 192, 32), Rect2(8544, 384, 160, 96), Rect2(8704, 640, 64, 128), Rect2(10560, 1280, 256, 64), Rect2(10432, 832, 96, 160), Rect2(2816, 2272, 256, 64), Rect2(2976, 1760, 128, 192), Rect2(8736, 1664, 256, 16), Rect2(8128, 1760, 160, 32), Rect2(1248, 2272, 160, 16), Rect2(832, 2240, 128, 16), Rect2(832, 2336, 192, 32), Rect2(1536, 2272, 224, 96), Rect2(768, 1664, 160, 192), Rect2(1120, 1664, 96, 96), Rect2(4384, 576, 224, 16), Rect2(4672, 576, 256, 16), Rect2(4960, 576, 128, 16), Rect2(4480, 672, 256, 32), Rect2(4608, 128, 160, 64), Rect2(7200, 1184, 224, 16), Rect2(6912, 1280, 192, 32), Rect2(6656, 1216, 128, 96), Rect2(6752, 640, 96, 192), Rect2(7200, 1696, 160, 16), Rect2(7552, 1728, 160, 16)],
	"spawns": [{
	"boss_id": 0,
	"chamber_id": 1,
	"id": "guardian_0",
	"kind": "boss",
	"patrol": Vector2(2592, 2592),
	"polarity": 1,
	"position": Vector2(2592, 1158)
	}, {
	"boss_id": 1,
	"chamber_id": 2,
	"id": "guardian_1",
	"kind": "boss",
	"patrol": Vector2(7264, 7264),
	"polarity": 0,
	"position": Vector2(7264, 2662)
	}, {
	"boss_id": 2,
	"chamber_id": 3,
	"id": "guardian_2",
	"kind": "boss",
	"patrol": Vector2(10752, 10752),
	"polarity": 0,
	"position": Vector2(10752, 678)
	}, {
	"boss_id": -1,
	"chamber_id": 17,
	"id": "enemy_0",
	"kind": "breaker",
	"patrol": Vector2(6544, 6544),
	"polarity": 0,
	"position": Vector2(6544, 1290),
	"support": Rect2(6400, 1312, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 5,
	"id": "enemy_1",
	"kind": "flyer",
	"patrol": Vector2(5232, 5328),
	"polarity": 1,
	"position": Vector2(5280, 1200),
	"support": Rect2(5184, 1376, 192, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 5,
	"id": "enemy_2",
	"kind": "flyer",
	"patrol": Vector2(5424, 5584),
	"polarity": 0,
	"position": Vector2(5504, 1296),
	"support": Rect2(5376, 1472, 256, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 9,
	"id": "enemy_3",
	"kind": "shifter",
	"patrol": Vector2(9264, 9264),
	"polarity": 1,
	"position": Vector2(9264, 618),
	"support": Rect2(9120, 640, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 14,
	"id": "enemy_4",
	"kind": "shifter",
	"patrol": Vector2(8912, 8912),
	"polarity": 0,
	"position": Vector2(8912, 1642),
	"support": Rect2(8768, 1664, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 14,
	"id": "enemy_5",
	"kind": "shifter",
	"patrol": Vector2(8224, 8224),
	"polarity": 0,
	"position": Vector2(8224, 1738),
	"support": Rect2(8080, 1760, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 4,
	"id": "enemy_6",
	"kind": "flyer",
	"patrol": Vector2(4432, 4528),
	"polarity": 0,
	"position": Vector2(4480, 2160),
	"support": Rect2(4384, 2336, 192, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 14,
	"id": "enemy_7",
	"kind": "walker",
	"patrol": Vector2(8592, 8688),
	"polarity": 0,
	"position": Vector2(8640, 1450),
	"support": Rect2(8496, 1472, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 7,
	"id": "enemy_8",
	"kind": "flyer",
	"patrol": Vector2(3984, 4080),
	"polarity": 1,
	"position": Vector2(4032, 1200),
	"support": Rect2(3936, 1376, 192, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 17,
	"id": "enemy_9",
	"kind": "laser",
	"patrol": Vector2(6752, 6752),
	"polarity": 1,
	"position": Vector2(6752, 1194),
	"support": Rect2(6608, 1216, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 16,
	"id": "enemy_10",
	"kind": "flyer",
	"patrol": Vector2(4432, 4528),
	"polarity": 1,
	"position": Vector2(4480, 400),
	"support": Rect2(4384, 576, 192, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 11,
	"id": "enemy_11",
	"kind": "laser",
	"patrol": Vector2(8496, 8496),
	"polarity": 0,
	"position": Vector2(8496, 714),
	"support": Rect2(8352, 736, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 12,
	"id": "enemy_12",
	"kind": "breaker",
	"patrol": Vector2(10768, 10768),
	"polarity": 1,
	"position": Vector2(10768, 1258),
	"support": Rect2(10624, 1280, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 7,
	"id": "enemy_13",
	"kind": "builder",
	"patrol": Vector2(4000, 4000),
	"polarity": 0,
	"position": Vector2(4000, 1450),
	"support": Rect2(3856, 1472, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 7,
	"id": "enemy_14",
	"kind": "turret",
	"patrol": Vector2(3808, 3808),
	"polarity": 0,
	"position": Vector2(3808, 1386),
	"support": Rect2(3664, 1408, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 7,
	"id": "enemy_15",
	"kind": "breaker",
	"patrol": Vector2(4080, 4080),
	"polarity": 1,
	"position": Vector2(4080, 1354),
	"support": Rect2(3936, 1376, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 10,
	"id": "enemy_16",
	"kind": "laser",
	"patrol": Vector2(10448, 10448),
	"polarity": 0,
	"position": Vector2(10448, 1866),
	"support": Rect2(10304, 1888, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 11,
	"id": "enemy_17",
	"kind": "flyer",
	"patrol": Vector2(7952, 8048),
	"polarity": 1,
	"position": Vector2(8000, 560),
	"support": Rect2(7904, 736, 192, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 6,
	"id": "enemy_18",
	"kind": "turret",
	"patrol": Vector2(8944, 8944),
	"polarity": 0,
	"position": Vector2(8944, 2506),
	"support": Rect2(8800, 2528, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 11,
	"id": "enemy_19",
	"kind": "turret",
	"patrol": Vector2(7936, 7936),
	"polarity": 1,
	"position": Vector2(7936, 714),
	"support": Rect2(7792, 736, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 5,
	"id": "enemy_20",
	"kind": "breaker",
	"patrol": Vector2(4960, 4960),
	"polarity": 0,
	"position": Vector2(4960, 810),
	"support": Rect2(4816, 832, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 10,
	"id": "enemy_21",
	"kind": "breaker",
	"patrol": Vector2(10240, 10240),
	"polarity": 0,
	"position": Vector2(10240, 1642),
	"support": Rect2(10096, 1664, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 13,
	"id": "enemy_22",
	"kind": "walker",
	"patrol": Vector2(2552, 2624),
	"polarity": 0,
	"position": Vector2(2576, 1834),
	"support": Rect2(2432, 1856, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 6,
	"id": "enemy_23",
	"kind": "breaker",
	"patrol": Vector2(8928, 8928),
	"polarity": 0,
	"position": Vector2(8928, 2346),
	"support": Rect2(8784, 2368, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 19,
	"id": "enemy_24",
	"kind": "breaker",
	"patrol": Vector2(8192, 8192),
	"polarity": 0,
	"position": Vector2(8192, 1130),
	"support": Rect2(8048, 1152, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 7,
	"id": "enemy_25",
	"kind": "builder",
	"patrol": Vector2(3776, 3776),
	"polarity": 1,
	"position": Vector2(3776, 1482),
	"support": Rect2(3632, 1504, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 8,
	"id": "enemy_26",
	"kind": "flyer",
	"patrol": Vector2(9456, 9584),
	"polarity": 0,
	"position": Vector2(9520, 2512),
	"support": Rect2(9408, 2688, 224, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 19,
	"id": "enemy_27",
	"kind": "builder",
	"patrol": Vector2(8016, 8016),
	"polarity": 0,
	"position": Vector2(8016, 1290),
	"support": Rect2(7872, 1312, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 5,
	"id": "enemy_28",
	"kind": "laser",
	"patrol": Vector2(4928, 4928),
	"polarity": 1,
	"position": Vector2(4928, 1290),
	"support": Rect2(4784, 1312, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 8,
	"id": "enemy_29",
	"kind": "breaker",
	"patrol": Vector2(10496, 10496),
	"polarity": 0,
	"position": Vector2(10496, 2666),
	"support": Rect2(10352, 2688, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 10,
	"id": "enemy_30",
	"kind": "laser",
	"patrol": Vector2(10272, 10272),
	"polarity": 1,
	"position": Vector2(10272, 1962),
	"support": Rect2(10128, 1984, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 13,
	"id": "enemy_31",
	"kind": "flyer",
	"patrol": Vector2(2400, 2496),
	"polarity": 0,
	"position": Vector2(2448, 2160),
	"support": Rect2(2352, 2336, 192, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 9,
	"id": "enemy_32",
	"kind": "shifter",
	"patrol": Vector2(9552, 9552),
	"polarity": 1,
	"position": Vector2(9552, 618),
	"support": Rect2(9408, 640, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 11,
	"id": "enemy_33",
	"kind": "walker",
	"patrol": Vector2(8728, 8744),
	"polarity": 0,
	"position": Vector2(8736, 618),
	"support": Rect2(8592, 640, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 17,
	"id": "enemy_34",
	"kind": "turret",
	"patrol": Vector2(7312, 7312),
	"polarity": 0,
	"position": Vector2(7312, 1162),
	"support": Rect2(7168, 1184, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 13,
	"id": "enemy_35",
	"kind": "laser",
	"patrol": Vector2(2688, 2688),
	"polarity": 0,
	"position": Vector2(2688, 2314),
	"support": Rect2(2544, 2336, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 10,
	"id": "enemy_36",
	"kind": "laser",
	"patrol": Vector2(9904, 9904),
	"polarity": 0,
	"position": Vector2(9904, 1962),
	"support": Rect2(9760, 1984, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 16,
	"id": "enemy_37",
	"kind": "builder",
	"patrol": Vector2(4400, 4400),
	"polarity": 0,
	"position": Vector2(4400, 682),
	"support": Rect2(4256, 704, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 15,
	"id": "enemy_38",
	"kind": "walker",
	"patrol": Vector2(1216, 1312),
	"polarity": 1,
	"position": Vector2(1264, 2346),
	"support": Rect2(1120, 2368, 288, 32)
	}, {
	"boss_id": -1,
	"chamber_id": 16,
	"id": "enemy_39",
	"kind": "turret",
	"patrol": Vector2(4704, 4704),
	"polarity": 1,
	"position": Vector2(4704, 554),
	"support": Rect2(4560, 576, 288, 32)
	}],
	"start_position": Vector2(6144, 2282),
	"tunnels": [{
	"a": 4,
	"b": 0,
	"height": 256,
	&"id": 0,
	"pieces": [Rect2(5024, 2112, 64, 256), Rect2(5088, 2112, 64, 256), Rect2(5152, 2080, 64, 256), Rect2(5216, 2080, 64, 256), Rect2(5280, 2080, 64, 256), Rect2(5344, 2048, 64, 256), Rect2(5408, 2048, 32, 256)],
	"rect": Rect2(5024, 2048, 416, 320),
	"type": "tunnel",
	&"weight": 386.88
	}, {
	"a": 7,
	"b": 5,
	"height": 224,
	&"id": 1,
	"pieces": [Rect2(4160, 1280, 64, 224), Rect2(4224, 1280, 64, 224), Rect2(4288, 1280, 64, 224), Rect2(4352, 1280, 64, 224), Rect2(4416, 1248, 64, 224), Rect2(4480, 1248, 64, 224), Rect2(4544, 1248, 64, 224), Rect2(4608, 1248, 64, 224), Rect2(4672, 1248, 32, 224)],
	"rect": Rect2(4160, 1248, 544, 256),
	"type": "tunnel",
	&"weight": 652.8
	}, {
	"a": 13,
	"b": 4,
	"height": 192,
	&"id": 2,
	"pieces": [Rect2(3328, 2144, 64, 192), Rect2(3392, 2144, 64, 192), Rect2(3456, 2144, 64, 192), Rect2(3520, 2144, 64, 192), Rect2(3584, 2144, 64, 192), Rect2(3648, 2144, 64, 192), Rect2(3712, 2144, 64, 192), Rect2(3776, 2176, 64, 192), Rect2(3840, 2176, 64, 192), Rect2(3904, 2176, 64, 192), Rect2(3968, 2176, 64, 192), Rect2(4032, 2176, 64, 192), Rect2(4096, 2176, 64, 192), Rect2(4160, 2176, 64, 192), Rect2(4224, 2176, 64, 192)],
	"rect": Rect2(3328, 2144, 960, 224),
	"type": "tunnel",
	&"weight": 1161.6
	}, {
	"a": 15,
	"b": 13,
	"height": 192,
	&"id": 3,
	"pieces": [Rect2(1824, 2176, 64, 192), Rect2(1888, 2176, 64, 192), Rect2(1952, 2176, 64, 192), Rect2(2016, 2176, 64, 192), Rect2(2080, 2144, 64, 192), Rect2(2144, 2144, 64, 192), Rect2(2208, 2144, 64, 192), Rect2(2272, 2144, 64, 192), Rect2(2336, 2144, 32, 192)],
	"rect": Rect2(1824, 2144, 544, 224),
	"type": "tunnel",
	&"weight": 500.48
	}, {
	"a": 5,
	"b": 17,
	"height": 224,
	&"id": 4,
	"pieces": [Rect2(5632, 1248, 64, 224), Rect2(5696, 1248, 64, 224), Rect2(5760, 1216, 64, 224), Rect2(5824, 1216, 64, 224), Rect2(5888, 1184, 64, 224), Rect2(5952, 1184, 64, 224), Rect2(6016, 1152, 64, 224), Rect2(6080, 1152, 64, 224), Rect2(6144, 1152, 64, 224), Rect2(6208, 1120, 64, 224), Rect2(6272, 1120, 64, 224), Rect2(6336, 1088, 64, 224), Rect2(6400, 1088, 32, 224)],
	"rect": Rect2(5632, 1088, 800, 384),
	"type": "tunnel",
	&"weight": 1240.0
	}, {
	"a": 17,
	"b": 19,
	"height": 192,
	&"id": 5,
	"pieces": [Rect2(7520, 1120, 64, 192), Rect2(7584, 1120, 64, 192), Rect2(7648, 1120, 64, 192), Rect2(7712, 1120, 64, 192), Rect2(7776, 1120, 64, 192), Rect2(7840, 1120, 64, 192), Rect2(7904, 1120, 64, 192), Rect2(7968, 1120, 32, 192)],
	"rect": Rect2(7520, 1120, 480, 192),
	"type": "tunnel",
	&"weight": 398.4
	}, {
	"a": 18,
	"b": 14,
	"height": 256,
	&"id": 6,
	"pieces": [Rect2(7712, 1568, 64, 256), Rect2(7776, 1568, 64, 256), Rect2(7840, 1536, 64, 256)],
	"rect": Rect2(7712, 1536, 192, 288),
	"type": "tunnel",
	&"weight": 138.24
	}, {
	"a": 6,
	"b": 8,
	"height": 160,
	&"id": 7,
	"pieces": [Rect2(8992, 2368, 64, 160), Rect2(9056, 2400, 64, 160), Rect2(9120, 2432, 64, 160), Rect2(9184, 2464, 64, 160), Rect2(9248, 2464, 64, 160), Rect2(9312, 2496, 64, 160), Rect2(9376, 2528, 64, 160)],
	"rect": Rect2(8992, 2368, 448, 320),
	"type": "tunnel",
	&"weight": 654.08
	}, {
	"a": 11,
	"b": 9,
	"height": 224,
	&"id": 8,
	"pieces": [Rect2(8864, 544, 64, 224), Rect2(8928, 544, 64, 224), Rect2(8992, 544, 64, 224), Rect2(9056, 544, 64, 224), Rect2(9120, 544, 32, 224)],
	"rect": Rect2(8864, 544, 288, 224),
	"type": "tunnel",
	&"weight": 204.48
	}, {
	"a": 9,
	"b": 3,
	"height": 224,
	&"id": 9,
	"pieces": [Rect2(9856, 544, 64, 224), Rect2(9920, 544, 64, 224), Rect2(9984, 544, 64, 224), Rect2(10048, 544, 64, 224), Rect2(10112, 512, 64, 224), Rect2(10176, 512, 64, 224), Rect2(10240, 512, 64, 224)],
	"rect": Rect2(9856, 512, 448, 256),
	"type": "tunnel",
	&"weight": 658.56
	}, {
	"a": 14,
	"b": 10,
	"height": 224,
	&"id": 10,
	"pieces": [Rect2(9056, 1568, 64, 224), Rect2(9120, 1600, 64, 224), Rect2(9184, 1600, 64, 224), Rect2(9248, 1632, 64, 224), Rect2(9312, 1632, 64, 224), Rect2(9376, 1664, 64, 224), Rect2(9440, 1664, 64, 224), Rect2(9504, 1696, 64, 224), Rect2(9568, 1696, 64, 224), Rect2(9632, 1728, 64, 224), Rect2(9696, 1728, 64, 224), Rect2(9760, 1760, 64, 224)],
	"rect": Rect2(9056, 1568, 768, 416),
	"type": "tunnel",
	&"weight": 829.44
	}]
	}
