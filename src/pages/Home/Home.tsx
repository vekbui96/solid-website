// @ts-ignore
import styles from "./Home.scss?inline"

export const Home = () => {
    return (
        <>
        <style>{styles}</style>
        <section class="home-placeholder">
            <p class="eyebrow">Portfolio</p>
            <h1 class="home-title">Coming soon</h1>
            <p class="home-sub">
                This page is under construction. In the meantime, take a look at my
                {" "}<strong>Experience</strong> and <strong>About</strong>.
            </p>
        </section>
        </>
    )
}
