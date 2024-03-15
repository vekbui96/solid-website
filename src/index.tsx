import { render } from 'solid-js/web';
import { Header } from './pages/Header/header.jsx'
import { HeroArea } from './pages/HeroArea/HeroArea.jsx'
import ThreeBackground from './pages/ThreeBackground/ThreeBackground.jsx'

// @ts-ignore
import styles from './index.scss?inline'

const MainPage = () => {
    return (<>
        <style>{styles}</style>
        <div class="website-container">
            <Header />
            <ThreeBackground class="ThreeBackground"/>
        </div>
    </>
    )
}

render(() => <MainPage/>, document.getElementById('app'));