import { customElement } from 'solid-element';
import { render } from 'solid-js/web';
import {Header} from './pages/Header/header.jsx'
import { HeroArea } from './pages/HeroArea/HeroArea.jsx'

const MainPage = () => {
    return (<>
        <Header/>
        <HeroArea/>
    </>)
}

render(() => <MainPage></MainPage>, document.getElementById('app'));