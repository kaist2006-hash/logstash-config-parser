"""Replay aggregate card logs through Logstash 8.17.6's JRuby/Event runtime."""
import argparse
import os
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--logstash-home", type=Path, required=True)
    parser.add_argument("--logs-dir", type=Path, required=True)
    parser.add_argument("--map", type=Path, default=Path(__file__).with_name("replay_map.json"))
    parser.add_argument("--workers", type=int, choices=range(1, 9), default=2)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.report.exists():
        parser.error("report already exists; choose a new filename")

    home = args.logstash_home.resolve()
    here = Path(__file__).resolve().parent
    version = home / "logstash-core/versions-gem-copy.yml"
    if not version.exists() or "8.17.6" not in version.read_text(encoding="utf-8"):
        parser.error("expected the Logstash 8.17.6 distribution")
    java = home / "jdk/bin" / ("java.exe" if os.name == "nt" else "java")
    if not java.exists():
        parser.error("bundled Java executable not found")

    env = os.environ.copy()
    env.update(
        CARD_PARSER_DIR=str(here.parent),
        CARD_CORE_WORKERS=str(args.workers),
        CARD_CORE_REPORT=str(args.report.resolve()),
        CARD_CORE_SCRIPT=str(here / "core_replay.rb"),
        CARD_LOG_DIR=str(args.logs_dir.resolve()),
        CARD_REPLAY_MAP=str(args.map.resolve()),
    )
    args.report.parent.mkdir(parents=True, exist_ok=True)
    classpath = os.pathsep.join(
        [str(home / "vendor/jruby/lib/jruby.jar"), str(home / "logstash-core/lib/jars/*")]
    )
    bootstrap = (
        'Java::OrgLogstash::RubyUtil::RUBY.evalScriptlet('
        '"$LOAD_PATH.replace(" + $LOAD_PATH.inspect + ");" + '
        'File.read(ENV.fetch("CARD_CORE_SCRIPT")))'
    )
    command = [
        str(java),
        "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
        "--add-opens=java.base/java.io=ALL-UNNAMED",
        "-Djruby.native.enabled=false",
        "-Djruby.jit.threshold=-1",
        f"-Djruby.home={home / 'vendor/jruby'}",
        "-Xms256m",
        "-Xmx1536m",
        "-cp",
        classpath,
        "org.jruby.Main",
        "-I",
        str(home / "logstash-core/lib"),
        "-rlogstash-core",
        "-e",
        bootstrap,
    ]
    raise SystemExit(subprocess.call(command, env=env))


if __name__ == "__main__":
    main()
