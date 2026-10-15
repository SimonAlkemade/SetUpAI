import pytest

from protocol import Config, pack_frame, parse_config, unpack_frame


def test_frame_round_trip():
    data = pack_frame(7, b"\xff\xd8jpeg")
    assert data[:4] == b"\x07\x00\x00\x00"  # uint32 little-endian, as Godot's encode_u32
    assert unpack_frame(data) == (7, b"\xff\xd8jpeg")


def test_frame_id_wraps_at_32_bits():
    assert unpack_frame(pack_frame(2**32 + 3, b"x")) == (3, b"x")


def test_short_frame_rejected():
    with pytest.raises(ValueError):
        unpack_frame(b"\x01\x02")


def test_config_defaults():
    cfg = parse_config({"type": "config"})
    assert cfg == Config()
    assert cfg.prompt and 0.0 < cfg.strength <= 1.0


def test_config_merges_onto_previous():
    base = parse_config({"prompt": "a medieval town", "seed": 3})
    cfg = parse_config({"strength": 0.7}, base)
    assert (cfg.prompt, cfg.seed, cfg.strength) == ("a medieval town", 3, 0.7)


def test_config_clamps_and_snaps():
    cfg = parse_config({"strength": 5, "blend": -1, "size": [333, 190]})
    assert cfg.strength == 1.0
    assert cfg.blend == 0.0
    # The VAE works on 8x8 blocks; the UNet wants multiples of 64 to avoid padding.
    assert cfg.size == (320, 192)


def test_config_ignores_unknown_keys():
    assert parse_config({"bogus": 1}) == Config()
