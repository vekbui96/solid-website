import { Switch, Match } from 'solid-js';
import { customElement } from 'solid-element';
import { Header } from './pages/Header/header'
import { Home } from './pages/Home/Home'
import { ExperiencePage } from './pages/Experience/Experience'
import { About } from './pages/About/About'
import { Projects } from './pages/Projects/Projects'

// @ts-ignore
import styles from './index.scss?inline'
import { GlobalContextProvider, useGlobalContext } from './context/GlobalContext';

const MainPage = () => {
    const context = useGlobalContext();
    return (<>
        <style>{styles}</style>
        <div class="site">
            <Header />
            <main class="content">
                <Switch fallback={<Home/>}>
                    <Match when={context?.page() === "home"}><Home/></Match>
                    <Match when={context?.page() === "experience"}><ExperiencePage/></Match>
                    <Match when={context?.page() === "about"}><About/></Match>
                    <Match when={context?.page() === "projects"}><Projects/></Match>
                </Switch>
            </main>
        </div>
    </>
    )
}
customElement('main-page', props => (
    <GlobalContextProvider>
        <MainPage />
    </GlobalContextProvider>
))
