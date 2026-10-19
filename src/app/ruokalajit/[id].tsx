import { useLocalSearchParams } from 'expo-router';
import { DishForm } from '@/screens/dishes';
export default function Screen(){const {id}=useLocalSearchParams<{id:string}>();return <DishForm key={id} id={id}/>;}
