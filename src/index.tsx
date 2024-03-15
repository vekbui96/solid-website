import { render } from 'solid-js/web';
import { customElement } from 'solid-element';
import { Header } from './pages/Header/header.jsx'
import { HeroArea } from './pages/HeroArea/HeroArea.jsx'
import ThreeBackground from './pages/ThreeBackground/ThreeBackground.jsx'

// @ts-ignore
import styles from './index.scss?inline'

const MainPage = () => {
    return (<>
        <style>{styles}</style>            
        <ThreeBackground/>
        
        <div class="website-container">
            <Header />
            <div class="display-manager">test</div>
        </div>
    </>
    )
}
customElement('main-page', props =>(
    <MainPage/>
))