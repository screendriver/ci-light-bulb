import { Store } from 'vuex';
import { State, Mutations, BuildStatus } from '@/store';

const bulbName = 'icolorlive';
const serviceName = 'f000ffa0-0451-4000-b000-000000000000';
const changeModeCharacteristic = 'f000ffa3-0451-4000-b000-000000000000';
// 4d43 (0x4F43) changes to color
// 4d57 (0x4F57) changes to white
const changeColorCharacteristic = 'f000ffa4-0451-4000-b000-000000000000';

export const enum BulbColor {
  OFF,
  BLUE,
  YELLOW,
  GREEN,
  RED,
  PINK,
}
type BulbColorRgb = [number, number, number];
type DeviceId = string;

function assertUnreachable(_x: never): never {
  throw new Error("Didn't expect to get here");
}

function getRgb(color: BulbColor): BulbColorRgb {
  switch (color) {
    case BulbColor.OFF:
      return [0, 0, 0];
    case BulbColor.BLUE:
      return [0, 0, 26];
    case BulbColor.YELLOW:
      return [26, 26, 0];
    case BulbColor.GREEN:
      return [0, 26, 0];
    case BulbColor.RED:
      return [26, 0, 0];
    case BulbColor.PINK:
      return [26, 0, 26];
  }
  return assertUnreachable(color);
}

interface WriteParams {
  service: string;
  characteristic: string;
  value: [number, number, number];
}

async function writeValue(
  gattServer: BluetoothRemoteGATTServer,
  params: WriteParams,
) {
  const service = await gattServer.getPrimaryService(params.service);
  const characteristic = await service.getCharacteristic(params.characteristic);
  await characteristic.writeValue(new Uint8Array(params.value));
}

export async function connect(): Promise<
  [BluetoothRemoteGATTServer, DeviceId]
> {
  if (!navigator.bluetooth) {
    throw new Error('Web Bluetooth is not supported on this platform');
  }
  const device = await navigator.bluetooth.requestDevice({
    filters: [{ name: bulbName }],
    optionalServices: [serviceName],
  });
  const gattServer = await device.gatt!.connect();
  return [gattServer, device.id];
}

export function disconnect(gattServer: BluetoothRemoteGATTServer) {
  gattServer.disconnect();
}

export async function fetchBuildStatus(
  apiUrl: string,
  apiToken: string,
  owner: string,
  repo: string,
  fetcher = fetch,
): Promise<BuildStatus> {
  const fullUrl = `${apiUrl}/repos/${owner}/${repo}/commits/master/statuses`;
  const response = await fetcher(fullUrl, {
    headers: {
      Authorization: `Bearer ${apiToken}`,
    },
  });
  const statuses = await response.json();
  const { id, state } = statuses[0];
  return { id, state };
}

export function changeColor(
  color: BulbColor,
  gattServer: BluetoothRemoteGATTServer,
) {
  return writeValue(gattServer, {
    service: serviceName,
    characteristic: changeColorCharacteristic,
    value: getRgb(color),
  });
}

export function getColorFromStatus(status: BuildStatus): BulbColor {
  switch (status.state) {
    case 'pending':
      return BulbColor.YELLOW;
    case 'failure':
    case 'error':
      return BulbColor.RED;
    case 'success':
      return BulbColor.GREEN;
    default:
      return BulbColor.PINK;
  }
}