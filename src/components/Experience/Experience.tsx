import { For, Show } from "solid-js";
import experiences from "../../data/experience.json";
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
    return (
        <div class="experience-container">
            <h2>{props.company}</h2>
            <div class="experience-position-date">
                <h2>{props.position}</h2>
                <h3>
                    {props.startDate.getFullYear()} - {props.endDate ? props.endDate.getFullYear() : "Current"}
                </h3>
            </div>
            <h3 class="experience-description">{props.description}</h3>
            <Show when={props.accomplishments}>
                <p>Accomplishments: {props.accomplishments}</p>
            </Show>
            <p>Skills: {props.skills}</p>
        </div>
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
                            startDate={new Date(exp.startDate)}
                            endDate={exp.endDate ? new Date(exp.endDate) : undefined}
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
