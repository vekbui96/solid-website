import { customElement } from 'solid-element';
import { Header } from './pages/Header/header'
import { Home } from './pages/Home/Home'

// @ts-ignore
import styles from './index.scss?inline'
import { GlobalContextProvider } from './context/GlobalContext';

const MainPage = () => {
    return (<>
        <style>{styles}</style>
        <div class="site">
            <Header />
            <main class="page-host">
                <Home />
            </main>
        </div>
    </>
    )
}
customElement('main-page', () => (
    <GlobalContextProvider>
        <MainPage />
    </GlobalContextProvider>
))
