"""Inject only a loopback HTTPS fixture URL into the generated XCTest plan."""
import argparse
import copy
from pathlib import Path
import plistlib
from urllib.parse import urlsplit


def configure(document, url):
    parsed = urlsplit(url)
    if (parsed.scheme != 'https' or parsed.hostname not in ['127.0.0.1', 'localhost']
            or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment
            or not parsed.port or not 1024 <= parsed.port <= 65535):
        raise ValueError('URL de relais HTTPS loopback requise')
    result = copy.deepcopy(document)
    targets = []
    if 'TestConfigurations' in result:
        for configuration in result['TestConfigurations']:
            if configuration.get('IsEnabled', True):
                targets.extend(target for target in configuration.get('TestTargets', [])
                               if target.get('BlueprintName') == 'DrivyTests')
    elif isinstance(result.get('DrivyTests'), dict):
        targets.append(result['DrivyTests'])
    if not targets:
        raise ValueError('Cible DrivyTests absente du plan XCTest')
    for target in targets:
        target.setdefault('EnvironmentVariables', {})['DRIVY_RELAY_QUALIFICATION_URL'] = url
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('products')
    parser.add_argument('url')
    args = parser.parse_args()
    products = Path(args.products).resolve()
    inputs = [path for path in products.glob('*.xctestrun') if path.name != 'Drivy-relay-qualification.xctestrun']
    if len(inputs) != 1:
        raise SystemExit('Plan XCTest source absent ou ambigu')
    output = products / 'Drivy-relay-qualification.xctestrun'
    # Keep the same directory: __TESTROOT__ paths must still resolve to the built products.
    output.write_bytes(plistlib.dumps(configure(plistlib.loads(inputs[0].read_bytes()), args.url)))
    print(output)
