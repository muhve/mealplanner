import { useLocalSearchParams } from 'expo-router';
import { HistoryTrip } from '@/screens/history';
export default function Screen(){const {id}=useLocalSearchParams<{id:string}>();return <HistoryTrip id={id}/>;}
