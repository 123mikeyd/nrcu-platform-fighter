from pathlib import Path
P=Path(__file__).resolve().parents[1]
s=(P/'scripts/frontend/how_to_play.gd').read_text()
assert '"name": "SHIELD"' not in s, 'structured help still advertises retired shield'
assert 'FRESH DIRECTION' in s, 'charge-store edge instruction missing'
assert '"mephisto": [' in s, 'Mephisto routes missing'
print('HELP_COMPLETE 3 checks')
