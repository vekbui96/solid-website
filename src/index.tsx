import { Switch, Match } from 'solid-js';
import { customElement } from 'solid-element';
import { Header } from './pages/Header/header'
import { Home } from './pages/Home/Home'
import { About } from './pages/About/About'
import { Projects } from './pages/Projects/Projects'
import ThreeBackground from './pages/ThreeBackground/ThreeBackground'

// @ts-ignore
import styles from './index.scss?inline'
import { GlobalContextProvider, useGlobalContext } from './context/GlobalContext';


document.addEventListener('touchmove', function (e) {
    e.preventDefault(); // This is to further ensure scrolling does not occur
}, { passive: false });

let lastTouchEnd = 0;
document.addEventListener('touchend', function (event) {
    const now = (new Date()).getTime();
    if (now - lastTouchEnd <= 300) {
        event.preventDefault();
    }
    lastTouchEnd = now;
}, false);


const MainPage = () => {
    const context = useGlobalContext();
    return (<>
        <style>{styles}</style>
        <div class="website-container">
            <ThreeBackground />
            <div class="content-container">
                <Header />
                <div class="display-manager">
                    <Switch fallback={<Home/>}>
                        <Match when={context?.page() === "home"}><Home/></Match>
                        <Match when={context?.page() === "about"}><About/></Match>
                        <Match when={context?.page() === "projects"}><Projects/></Match>
                    </Switch>
                </div>
            </div>
        </div>
    </>
    )
}
customElement('main-page', props => (
    <GlobalContextProvider>
        <MainPage />
    </GlobalContextProvider>
))