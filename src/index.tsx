import { render } from 'solid-js/web';
import { customElement } from 'solid-element';
import { Header } from './pages/Header/header.jsx'
import { HeroArea } from './pages/HeroArea/HeroArea.jsx'
import ThreeBackground from './pages/ThreeBackground/ThreeBackground.jsx'

// @ts-ignore
import styles from './index.scss?inline'


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
    return (<>
        <style>{styles}</style>            
        
        <div class="website-container">
            <ThreeBackground/>
            <div class="content-container">
                <Header />
                <div class="display-manager"><div>test</div>
                <div>test2</div></div>
            </div>
        </div>
    </>
    )
}
customElement('main-page', props =>(
    <MainPage/>
))