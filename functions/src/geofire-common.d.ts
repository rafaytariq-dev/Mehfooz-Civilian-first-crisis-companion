// Type declarations for geofire-common
declare module 'geofire-common' {
  export function geohashQueryBounds(
    center: [number, number],
    radiusInM: number
  ): [string, string][];

  export function distanceBetween(
    location1: [number, number],
    location2: [number, number]
  ): number;

  export function geohashForLocation(
    location: [number, number],
    precision?: number
  ): string;
}
