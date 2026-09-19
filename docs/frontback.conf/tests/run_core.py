"""Offline Logstash 8.17.6 Event/JRuby tests; no Beats or Elasticsearch."""
import argparse
import os
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--logstash-home", type=Path, required=True)
    parser.add_argument("--logs-dir", type=Path)
    parser.add_argument("--workers", type=int, choices=range(1, 9), default=1)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    if args.report.exists():
        parser.error("report already exists; choose a new path")
    home = args.logstash_home.resolve()
    version_file = home / "logstash-core" / "versions-gem-copy.yml"
    if not version_file.exists() or "8.17.6" not in version_file.read_text(encoding="utf-8"):
        parser.error("expected Logstash 8.17.6")
    java = home / "jdk" / "bin" / ("java.exe" if os.name == "nt" else "java")
    if not java.exists():
        parser.error("bundled Java executable not found")

    here = Path(__file__).resolve().parent
    env = os.environ.copy()
    env.update(
        FRONTBACK_PARSER_DIR=str(here.parent),
        FRONTBACK_CORE_WORKERS=str(args.workers),
        FRONTBACK_CORE_REPORT=str(args.report.resolve()),
        FRONTBACK_CORE_SCRIPT=str(here / "core_replay.rb"),
    )
    if args.logs_dir:
        env.pop("FRONTBACK_CONTRACTS", None)
        env["FRONTBACK_LOG_DIR"] = str(args.logs_dir.resolve())
    else:
        env["FRONTBACK_CONTRACTS"] = "1"

    args.report.parent.mkdir(parents=True, exist_ok=True)
    classpath = os.pathsep.join(
        [str(home / "vendor" / "jruby" / "lib" / "jruby.jar"), str(home / "logstash-core" / "lib" / "jars" / "*")]
    )
    bootstrap = (
        'Java::OrgLogstash::RubyUtil::RUBY.evalScriptlet('
        '"$LOAD_PATH.replace(" + $LOAD_PATH.inspect + ");" + '
        'File.read(ENV.fetch("FRONTBACK_CORE_SCRIPT")))'
    )
    command = [
        str(java),
        "--add-opens=java.base/sun.nio.ch=ALL-UNNAMED",
        "--add-opens=java.base/java.io=ALL-UNNAMED",
        f"-Djruby.home={home / 'vendor' / 'jruby'}",
        "-Xms256m",
        "-Xmx1024m",
        "-cp",
        classpath,
        "org.jruby.Main",
        "-I",
        str(home / "logstash-core" / "lib"),
        "-rlogstash-core",
        "-e",
        bootstrap,
    ]
    raise SystemExit(subprocess.call(command, env=env))


if __name__ == "__main__":
    main()
