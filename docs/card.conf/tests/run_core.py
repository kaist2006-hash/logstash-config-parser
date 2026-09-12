"""Offline tests using the user's local Logstash 8.17.6 JDK/JRuby/Event libraries.
No Elasticsearch, Beats, network access, or third-party Python dependencies.
"""
import argparse, os, subprocess
from pathlib import Path

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--logstash-home',type=Path,required=True)
    ap.add_argument('--logs-dir',type=Path,help='Directory containing the original KB IC and Lotte MS samples')
    ap.add_argument('--workers',type=int,choices=range(1,9),default=1)
    ap.add_argument('--report',type=Path,required=True)
    args=ap.parse_args()
    if args.report.exists():ap.error('Report already exists; choose a new report filename')
    home=args.logstash_home.resolve();here=Path(__file__).resolve().parent
    version=home/'logstash-core/versions-gem-copy.yml'
    if not version.exists() or '8.17.6' not in version.read_text(encoding='utf8'):
        ap.error('Expected the Logstash 8.17.6 distribution')
    java=home/'jdk/bin'/('java.exe' if os.name=='nt' else 'java')
    if not java.exists():ap.error('Bundled Java executable not found')
    env=os.environ.copy()
    env.update(CARD_PARSER_DIR=str(here.parent),CARD_CORE_WORKERS=str(args.workers),CARD_CORE_REPORT=str(args.report.resolve()),CARD_CORE_SCRIPT=str(here/'core_replay.rb'))
    if args.logs_dir:
        env.pop('CARD_CONTRACT_FILE',None)
        env['CARD_LOG_DIR']=str(args.logs_dir.resolve())
    else:env['CARD_CONTRACT_FILE']=str(here/'contracts.jsonl')
    args.report.parent.mkdir(parents=True,exist_ok=True)
    cp=os.pathsep.join([str(home/'vendor/jruby/lib/jruby.jar'),str(home/'logstash-core/lib/jars/*')])
    bootstrap='Java::OrgLogstash::RubyUtil::RUBY.evalScriptlet("$LOAD_PATH.replace(" + $LOAD_PATH.inspect + ");" + File.read(ENV.fetch("CARD_CORE_SCRIPT")))'
    cmd=[str(java),'--add-opens=java.base/sun.nio.ch=ALL-UNNAMED','--add-opens=java.base/java.io=ALL-UNNAMED',f'-Djruby.home={home / "vendor/jruby"}','-Xms256m','-Xmx1024m','-cp',cp,'org.jruby.Main','-I',str(home/'logstash-core/lib'),'-rlogstash-core','-e',bootstrap]
    raise SystemExit(subprocess.call(cmd,env=env))

if __name__=='__main__':main()
