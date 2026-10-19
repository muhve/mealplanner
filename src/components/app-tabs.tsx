import { NativeTabs } from 'expo-router/native-tabs';
import { Platform } from 'react-native';
import { useTheme } from '@/hooks/use-theme';

export default function AppTabs() {
  const colors = useTheme();
  return <NativeTabs
    backgroundColor={colors.surface}
    tintColor={colors.accent}
    iconColor={{ default: colors.muted, selected: colors.accent }}
    labelStyle={{ default: { color: colors.muted }, selected: { color: colors.accent } }}>
    <NativeTabs.Trigger name="(ostoslista)">
      <NativeTabs.Trigger.Label>Ostoslista</NativeTabs.Trigger.Label>
      <NativeTabs.Trigger.Icon {...(Platform.OS === 'ios'
        ? { sf: 'cart' as const }
        : { src: require('@/assets/images/tabIcons/home.png') })} />
    </NativeTabs.Trigger>
    <NativeTabs.Trigger name="ruokalajit">
      <NativeTabs.Trigger.Label>Ruokalajit</NativeTabs.Trigger.Label>
      <NativeTabs.Trigger.Icon {...(Platform.OS === 'ios'
        ? { sf: 'fork.knife' as const }
        : { src: require('@/assets/images/tabIcons/explore.png') })} />
    </NativeTabs.Trigger>
  </NativeTabs>;
}
