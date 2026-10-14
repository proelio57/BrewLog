import { BookOpen, Droplet, Leaf, List, Wrench } from 'lucide-react'
import { useEffect, useLayoutEffect, useState } from 'react'
import { navigate, repository, restoredScrollY, settings, setup, useRoute } from './app'
import { requestPersistentStorage } from './data/db'
import { BeanEditor, BeanList } from './screens/Beans'
import { BrewDetail } from './screens/BrewDetail'
import { BrewSetupScreen } from './screens/BrewSetup'
import { EquipmentEditor, GearScreen, PresetPicker, SettingsScreen } from './screens/Gear'
import { Journal } from './screens/Journal'
import { LiveBrew } from './screens/LiveBrew'
import { Onboarding } from './screens/Onboarding'
import { QuickWeigh } from './screens/QuickWeigh'
import { RecipeDetail, RecipeEditor, RecipeList, RecipePicker } from './screens/Recipes'

const TABS = [
  { path: '/brew', label: 'Brew', icon: Droplet },
  { path: '/recipes', label: 'Recipes', icon: BookOpen },
  { path: '/journal', label: 'Journal', icon: List },
  { path: '/beans', label: 'Beans', icon: Leaf },
  { path: '/gear', label: 'Gear', icon: Wrench },
]

/** Route switch + tab bar. (Not called App.tsx: it would clash with app.ts on case-insensitive file systems.) */
export function Shell() {
  const [loaded, setLoaded] = useState(false)
  const route = useRoute()

  useEffect(() => {
    void repository.load().then(() => {
      setup.restore()
      setLoaded(true)
      void requestPersistentStorage()
      if (!settings.get().onboardingDone && !window.location.hash.startsWith('#/onboarding')) navigate('/onboarding', true)
    })
  }, [])

  // Each screen starts at the top; Back returns to where you were.
  useLayoutEffect(() => {
    window.scrollTo(0, restoredScrollY())
  }, [route, loaded])

  if (!loaded) return <div className="app" />

  const [first, second] = route.segments
  const isTab = TABS.some((t) => t.path === route.path)
  let screen
  switch (first) {
    case 'onboarding': screen = <Onboarding />; break
    case 'recipes': screen = <RecipeList />; break
    case 'journal': screen = <Journal />; break
    case 'beans': screen = <BeanList />; break
    case 'gear': screen = <GearScreen />; break
    case 'weigh': screen = <QuickWeigh />; break
    case 'live': screen = <LiveBrew />; break
    case 'recipe-picker': screen = <RecipePicker />; break
    case 'presets': screen = <PresetPicker />; break
    case 'settings': screen = <SettingsScreen />; break
    case 'brews': screen = <BrewDetail key={second} brewId={second ?? ''} isNew={route.query.get('new') === '1'} />; break
    case 'recipe': screen = <RecipeDetail key={second} recipeId={second ?? ''} />; break
    case 'recipe-edit': screen = <RecipeEditor key={second} recipeId={second ?? 'new'} duplicate={route.query.get('dup') === '1'} />; break
    case 'bean': screen = <BeanEditor key={second} beanId={second ?? 'new'} />; break
    case 'equipment': screen = <EquipmentEditor key={second} itemId={second ?? 'new'} />; break
    default: screen = <BrewSetupScreen />
  }

  return (
    <div className="app">
      {screen}
      {isTab && (
        <nav className="tabbar" aria-label="Main">
          {TABS.map((tab) => {
            const Icon = tab.icon
            return (
              <button key={tab.path} className={route.path === tab.path ? 'active' : ''} onClick={() => navigate(tab.path, true)}
                aria-current={route.path === tab.path ? 'page' : undefined}>
                <Icon size={22} />
                {tab.label}
              </button>
            )
          })}
        </nav>
      )}
    </div>
  )
}
