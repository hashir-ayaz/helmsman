package k8s

import (
	"context"
	"fmt"

	batchv1 "k8s.io/api/batch/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

const cronJobInstantiateAnnotation = "cronjob.kubernetes.io/instantiate"

// TriggerCronJob creates a one-off Job from a CronJob's jobTemplate, matching
// kubectl create job --from=cronjob/...
func TriggerCronJob(ctx context.Context, b *cluster.ClientBundle, namespace, name string) (string, error) {
	cronJob, err := b.Typed.BatchV1().CronJobs(namespace).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return "", fmt.Errorf("get cronjob %s/%s: %w", namespace, name, err)
	}

	job := &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:    namespace,
			GenerateName: cronJob.Name + "-",
			Labels:       copyStringMap(cronJob.Spec.JobTemplate.Labels),
			Annotations:  copyStringMap(cronJob.Spec.JobTemplate.Annotations),
		},
		Spec: cronJob.Spec.JobTemplate.Spec,
	}
	if job.Annotations == nil {
		job.Annotations = map[string]string{}
	}
	job.Annotations[cronJobInstantiateAnnotation] = "manual"

	controller := true
	block := true
	job.OwnerReferences = []metav1.OwnerReference{{
		APIVersion:         batchv1.SchemeGroupVersion.String(),
		Kind:               "CronJob",
		Name:               cronJob.Name,
		UID:                cronJob.UID,
		Controller:         &controller,
		BlockOwnerDeletion: &block,
	}}

	created, err := b.Typed.BatchV1().Jobs(namespace).Create(ctx, job, metav1.CreateOptions{})
	if err != nil {
		return "", fmt.Errorf("create job from cronjob %s/%s: %w", namespace, name, err)
	}
	return created.Name, nil
}

func copyStringMap(m map[string]string) map[string]string {
	if len(m) == 0 {
		return nil
	}
	out := make(map[string]string, len(m))
	for k, v := range m {
		out[k] = v
	}
	return out
}
