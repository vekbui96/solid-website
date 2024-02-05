import { customElement } from 'solid-element';
import { render } from 'solid-js/web';
import { Header } from './pages/Header/header.jsx'
import { HeroArea } from './pages/HeroArea/HeroArea.jsx'
import { SocialMedia } from './pages/SocialMedia/SocialMedia.jsx'
import { About } from './pages/About/About.jsx'
import { Testing } from '../src/components/Testing.jsx'

const MainPage = () => {
    return (<>
        <Header/>
        <HeroArea/>
        <About/>
        <Testing/>
    </>)
}

render(() => <MainPage></MainPage>, document.getElementById('app'));