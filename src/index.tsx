import { customElement } from 'solid-element';
import { render } from 'solid-js/web';
import { Header } from './pages/Header/header.jsx'
import { HeroArea } from './pages/HeroArea/HeroArea.jsx'
import { SocialMedia } from './pages/SocialMedia/SocialMedia.jsx'
import { About } from './pages/About/About.jsx'
// @ts-ignore
import styles from './index.scss?inline'

const MainPage = () => {
    return (<>
        <style>{styles}</style>
        <div class="website-container">
            <Header />
            <HeroArea />
        </div>
    </>
    )
}

render(() => <MainPage></MainPage>, document.getElementById('app'));