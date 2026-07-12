package k8s

import (
	"context"
	"testing"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	k8stesting "k8s.io/client-go/testing"
	"k8s.io/client-go/kubernetes/fake"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

func TestTriggerCronJob_createsJob(t *testing.T) {
	cronJob := &batchv1.CronJob{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "hourly",
			Namespace: "default",
			UID:       "uid-1",
		},
		Spec: batchv1.CronJobSpec{
			JobTemplate: batchv1.JobTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels:      map[string]string{"app": "test"},
					Annotations: map[string]string{"foo": "bar"},
				},
				Spec: batchv1.JobSpec{
					Template: corev1.PodTemplateSpec{
						Spec: corev1.PodSpec{
							RestartPolicy: corev1.RestartPolicyNever,
							Containers: []corev1.Container{{
								Name:  "c",
								Image: "busybox",
							}},
						},
					},
				},
			},
		},
	}
	clientset := fake.NewSimpleClientset(cronJob)
	var createdJob *batchv1.Job
	clientset.PrependReactor("create", "jobs", func(action k8stesting.Action) (bool, runtime.Object, error) {
		job := action.(k8stesting.CreateAction).GetObject().(*batchv1.Job).DeepCopy()
		if job.Name == "" && job.GenerateName != "" {
			job.Name = job.GenerateName + "manual"
		}
		createdJob = job
		return true, job, nil
	})
	b := &cluster.ClientBundle{Typed: clientset}

	name, err := TriggerCronJob(context.Background(), b, "default", "hourly")
	if err != nil {
		t.Fatal(err)
	}
	if name != "hourly-manual" {
		t.Errorf("returned name = %q, want hourly-manual", name)
	}
	if createdJob == nil {
		t.Fatal("expected create reactor to capture job")
	}
	if createdJob.Annotations[cronJobInstantiateAnnotation] != "manual" {
		t.Errorf("instantiate annotation = %q", createdJob.Annotations[cronJobInstantiateAnnotation])
	}
	if createdJob.Labels["app"] != "test" {
		t.Errorf("labels = %v", createdJob.Labels)
	}
	if createdJob.GenerateName != "hourly-" {
		t.Errorf("generateName = %q", createdJob.GenerateName)
	}
	if len(createdJob.OwnerReferences) != 1 || createdJob.OwnerReferences[0].Kind != "CronJob" {
		t.Errorf("ownerReferences = %v", createdJob.OwnerReferences)
	}
}

func TestTriggerCronJob_missingCronJob(t *testing.T) {
	b := &cluster.ClientBundle{Typed: fake.NewSimpleClientset()}
	if _, err := TriggerCronJob(context.Background(), b, "default", "missing"); err == nil {
		t.Fatal("expected error for missing cronjob")
	}
}
