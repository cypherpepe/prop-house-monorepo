import classes from "./ProposalEditor.module.css";
import { Row, Col, Form } from "react-bootstrap";
import { useAppSelector } from "../../hooks";
import { ProposalFields } from "../../utils/proposalFields";
import { useState } from "react";
import clsx from "clsx";

const ProposalEditor: React.FC<{
  onDataChange: (data: Partial<ProposalFields>) => void;
}> = (props) => {
  const data = useAppSelector((state) => state.editor.proposal);
  const { onDataChange } = props;
  const [blurred, setBlurred] = useState(false);

  const validateInput = (min: number, count: number) =>
    0 < count && count < min;

  const formData = [
    {
      title: "Title",
      type: "input",
      fieldValue: data.title,
      fieldName: "title",
      placeholder: "Give your proposal a name",
      value: "",
      minCount: 5,
      maxCount: 100,
      error: "Title must be 5 characters minimum",
    },
    {
      title: "tl;dr",
      type: "input",
      fieldValue: data.tldr,
      fieldName: "tldr",
      placeholder:
        "In the simplest language possible, explain your proposal in one sentence",
      value: "",
      minCount: 10,
      maxCount: 120,
      error: "TLDR must be between 10 & 120 characters",
    },
    {
      title: "Description",
      type: "textarea",
      fieldValue: data.what,
      fieldName: "what",
      placeholder:
        "Project details: what are you building?\nRoadmap: when do you expect to complete it by?\nTeam: who is building this?\nLinks: share relevant links to the team and project",
      value: "",
      minCount: 50,
      error: "Description must be 50 characters minimum",
    },
  ];

  return (
    <>
      <Row>
        <Col xl={12}>
          <Form>
            <Form.Group className={classes.inputGroup}>
              {formData.map((input) => {
                return (
                  <div className={classes.inputSection}>
                    <div className={classes.inputInfo}>
                      <Form.Label className={classes.inputLabel}>
                        {input.title}
                      </Form.Label>
                      <Form.Label className={classes.inputChars}>
                        {input.maxCount
                          ? `${input.fieldValue.length}/${input.maxCount}`
                          : input.fieldValue.length}
                      </Form.Label>
                    </div>

                    <Form.Control
                      as={input.type as any}
                      maxLength={input.maxCount && input.maxCount}
                      placeholder={input.placeholder}
                      className={clsx(
                        classes.input,
                        input.fieldName === "what" && classes.descriptionInput
                      )}
                      onChange={(e) => {
                        setBlurred(false);
                        onDataChange({ [input.fieldName]: e.target.value });
                      }}
                      value={data && input.fieldValue}
                      onBlur={() => {
                        setBlurred(true);
                      }}
                    />

                    {blurred &&
                      validateInput(
                        input.minCount,
                        input.fieldValue.length
                      ) && <p className={classes.inputError}>{input.error}</p>}
                  </div>
                );
              })}
            </Form.Group>
          </Form>
        </Col>
      </Row>
    </>
  );
};

export default ProposalEditor;
