Starting Caldera

python3 -m venv .calderavenv
source .calderavenv/bin/activate
cd caldera
pip3 install -r requirements.txt
python3 server.py --insecure --build


Adding plugins to caldera
git clone https://github.com/mitre/caldera-ot.git --recursive
ls
 cp -r ~/caldera-ot/modbus ~/caldera/plugins/
 cp -r ~/caldera-ot/dnp3 ~/caldera/plugins/
cd ~/caldera/conf/
vim default.yml
>add the plugins to the plugins section