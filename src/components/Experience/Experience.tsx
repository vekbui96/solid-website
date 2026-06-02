import { For, Show } from "solid-js";
import experiences from "../../data/experience.json";
// @ts-ignore
import styles from './Experience.scss?inline'

type ExperienceType = {
    company: string;
    position: string;
    startDate: Date;
    endDate?: Date;
    description: string;
    accomplishments?: string;
    skills: string;
}

export const Experience = (props: ExperienceType) => {
    const skills = () => props.skills.split(",").map((s) => s.trim()).filter(Boolean);

    return (
        <article class="experience-container">
            <div class="experience-header">
                <div class="experience-role">
                    <h3 class="experience-company">{props.company}</h3>
                    <p class="experience-position">{props.position}</p>
                </div>
                <span class="experience-dates">
                    {props.startDate.getFullYear()} – {props.endDate ? props.endDate.getFullYear() : "Present"}
                </span>
            </div>
            <p class="experience-description">{props.description}</p>
            <Show when={props.accomplishments}>
                <p class="experience-accomplishment">{props.accomplishments}</p>
            </Show>
            <div class="experience-skills">
                <For each={skills()}>
                    {(skill) => <span class="skill-tag">{skill}</span>}
                </For>
            </div>
        </article>
    )
}

export const ExperienceList = () => {
    return (
        <>
            <style>{styles}</style>
            <div class="experience-list">
                <For each={experiences}>
                    {(exp) => (
                        <Experience
                            company={exp.company}
                            position={exp.position}
                            startDate={new Date(exp.startDate + "T00:00:00")}
                            endDate={exp.endDate ? new Date(exp.endDate + "T00:00:00") : undefined}
                            description={exp.description}
                            accomplishments={exp.accomplishments}
                            skills={exp.skills}
                        />
                    )}
                </For>
            </div>
        </>
    )
}
