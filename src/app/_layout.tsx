import { DarkTheme, DefaultTheme, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import AppTabs from '@/components/app-tabs';
import { StoreProvider } from '@/data/store';
import { useColorScheme } from '@/hooks/use-color-scheme';
export default function Layout() { const scheme = useColorScheme(); return <ThemeProvider value={scheme === 'dark' ? DarkTheme : DefaultTheme}><StoreProvider><StatusBar style={scheme === 'dark' ? 'light' : 'dark'} /><AppTabs /></StoreProvider></ThemeProvider>; }
