"""Round-trip helper for the Erlang proto_roundtrip_SUITE CT test.

Reads a protobuf-encoded MarketEvent from the file given as argv[1],
decodes with the generated Python stubs, re-encodes, and writes the
raw bytes to stdout.  Erlang compares the output to its own encoding.
"""

import sys
import os

# Make the adapters/proto tree importable when run from the project root.
_HERE = os.path.dirname(os.path.abspath(__file__))
_PROTO_ROOT = os.path.dirname(_HERE)          # adapters/
sys.path.insert(0, os.path.dirname(_PROTO_ROOT))  # project root
sys.path.insert(0, _PROTO_ROOT)              # adapters/

from nba_polymarket.v1 import market_pb2  # noqa: E402


def main() -> None:
    if len(sys.argv) < 2:
        print("usage: roundtrip.py <input_file>", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1], "rb") as fh:
        raw = fh.read()

    event = market_pb2.MarketEvent()
    event.ParseFromString(raw)

    out = event.SerializeToString()
    sys.stdout.buffer.write(out)


if __name__ == "__main__":
    main()
