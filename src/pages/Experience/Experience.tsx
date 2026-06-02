import { ExperienceList } from "../../components/Experience/Experience";
// @ts-ignore
import styles from "./Experience.scss?inline"

export const ExperiencePage = () => {
    const startDate = new Date('January 30, 2020');
    const years = new Date().getFullYear() - startDate.getFullYear();

    return (
        <>
        <style>{styles}</style>
        <section class="experience-page">
            <p class="eyebrow">{years}+ years of experience</p>
            <h1 class="hero-title">Building scalable software across frontend, backend, cloud, and AI.</h1>
            <p class="hero-sub">
                Full-Stack Software Engineer focused on enterprise applications, scalable APIs,
                cloud infrastructure, and AI-driven workflows.
            </p>

            <h2 class="section-heading">Experience</h2>
            <ExperienceList />
        </section>
        </>
    )
}
