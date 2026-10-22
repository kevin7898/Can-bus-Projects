export type Transport = 'cellular' | 'wifi' | 'either'
export type UploadState = 'uploading' | 'waiting-wifi' | 'complete'

export interface UploadItem {
  id: string
  label: string
  detail: string
  sizeMb: number
  progress: number
  transport: Transport
  state: UploadState
}

export interface Trip {
  id: string
  day: string
  date: string
  time: string
  origin: string
  destination: string
  distanceKm: number
  duration: string
  economy: number
  maxSpeed: number
  score: number
  uploaded: boolean
  route: string
}

export const uploads: UploadItem[] = [
  { id: 'u1', label: 'Live trip summary', detail: 'Events + 1 Hz telemetry', sizeMb: 2.4, progress: 68, transport: 'cellular', state: 'uploading' },
  { id: 'u2', label: 'Raw CAN capture', detail: 'Drive CAN · 18 min', sizeMb: 186, progress: 24, transport: 'wifi', state: 'waiting-wifi' },
  { id: 'u3', label: 'Yesterday’s trips', detail: '4 trips · processed telemetry', sizeMb: 8.7, progress: 100, transport: 'either', state: 'complete' },
]

export const trips: Trip[] = [
  { id: 't1', day: 'Today', date: 'Oct 22', time: '07:42', origin: 'Home', destination: 'Downtown', distanceKm: 24.8, duration: '31 min', economy: 5.2, maxSpeed: 102, score: 91, uploaded: false, route: 'M18 91 C 52 90, 48 57, 83 61 S 118 24, 174 34 S 216 62, 258 20' },
  { id: 't2', day: 'Yesterday', date: 'Oct 21', time: '17:18', origin: 'Downtown', destination: 'Home', distanceKm: 26.1, duration: '44 min', economy: 5.8, maxSpeed: 96, score: 84, uploaded: true, route: 'M18 24 C 52 33, 49 66, 86 61 S 132 93, 166 73 S 224 69, 258 96' },
  { id: 't3', day: 'Monday', date: 'Oct 20', time: '12:06', origin: 'Home', destination: 'North Shore', distanceKm: 48.6, duration: '52 min', economy: 4.9, maxSpeed: 109, score: 94, uploaded: true, route: 'M18 86 C 41 51, 69 75, 92 43 S 140 39, 164 62 S 216 54, 258 17' },
]

export const chartData = [4.9, 5.1, 5.4, 5.2, 5.0, 5.7, 5.3, 4.8, 5.1, 5.2]
