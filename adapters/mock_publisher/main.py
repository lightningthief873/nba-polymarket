"""CLI entry-point for the mock ZMQ publisher."""

import argparse
import json
import sys
import time

import zmq

from publisher import Publisher


def parse_args(argv=None):
    p = argparse.ArgumentParser(description="Synthetic MarketEvent ZMQ publisher")
    p.add_argument("--rate",          type=float, default=1000.0,
                   help="Events per second (default: 1000)")
    p.add_argument("--duration",      type=float, default=30.0,
                   help="Run duration in seconds (default: 30)")
    p.add_argument("--seed",          type=int,   default=42,
                   help="RNG seed for reproducibility (default: 42)")
    p.add_argument("--condition-ids", type=str,   default="0xABCD,0x1234",
                   help="Comma-separated condition IDs to cycle through")
    p.add_argument("--bind",          type=str,   default="tcp://*:5555",
                   help="ZMQ bind address (default: tcp://*:5555)")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    condition_ids = [c.strip() for c in args.condition_ids.split(",") if c.strip()]

    ctx = zmq.Context()
    sock = ctx.socket(zmq.PUB)
    sock.bind(args.bind)

    # Give subscribers time to connect before the first message.
    time.sleep(0.1)

    pub = Publisher(sock, rate=args.rate, condition_ids=condition_ids, seed=args.seed)
    stats = pub.run(args.duration)

    print(json.dumps({"evt": "done", **stats}), flush=True)

    sock.close()
    ctx.term()


if __name__ == "__main__":
    sys.exit(main())
